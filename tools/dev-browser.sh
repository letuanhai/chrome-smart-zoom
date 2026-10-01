#!/bin/sh
# Launch a CDP-debuggable Chromium with this extension loaded unpacked, so
# nothing has to be installed or reloaded through chrome://extensions.
#
#   ./tools/dev-browser.sh                 # launch, then WATCH and reload the
#                                          #  extension on every relevant edit,
#                                          #  until Ctrl-C (which stops chrome)
#   ./tools/dev-browser.sh reload          # reload the extension, keep the browser
#   ./tools/dev-browser.sh stop            # kill it
#   ./tools/dev-browser.sh status          # WHICH browser is on the port
#
# One fixed port serves two devices, so that the MCP config never changes:
#   phone   - chrome runs HERE, X11-forwarded to the phone, CDP is local.
#   laptop  - chrome runs THERE, `ssh -R 9333:localhost:9222` puts its CDP
#             on this port instead; don't run this script at all.
# They collide only if a browser here is still holding the port when the
# laptop connects. Mostly it is not: chrome EXITS when its X display goes
# away (measured - kill the X server and the process is gone, port free),
# so leaving the phone usually clears it by itself. When the ssh session
# lingers instead, `ssh -o ExitOnForwardFailure=yes -R ...` from the laptop
# refuses to connect rather than leaving you pointed at the stale browser
# here, and `dev-browser.sh stop` over ssh frees it. `status` says which
# one you are actually on.
#
# The debug port is always on 127.0.0.1: --remote-debugging-address is accepted
# and then silently IGNORED (measured on 151/153 - `ss -ltn` shows 127.0.0.1
# with =0.0.0.0 and with an explicit interface address alike), so anything off
# this box reaches it through ssh or not at all.
#   PORT=9334 ./tools/dev-browser.sh       # another port, if 9333 is taken too
#   CLEAN=1 ./tools/dev-browser.sh         # start from an empty profile
#   WATCH=0 ./tools/dev-browser.sh         # launch and return, don't watch
#   URL= ./tools/dev-browser.sh            # don't open a test page at startup
#   WINDOW=1600,1000 ./tools/dev-browser.sh  # window size (default: fill the
#                                          #  display; WINDOW= to opt out)
#   ./tools/dev-browser.sh --headless=new  # extra flags pass through
#
# popup.html/popup.js edits need NOTHING here - just reopen the popup. What
# needs an EXTENSION reload (then a reload of the page under test): manifest.json,
# background.js and the content scripts js/zoom.js, js/inject.js.
#
# A foreground run does that reload for you, watching exactly those files.
# `dev-browser.sh reload` is the same thing on demand, from another shell.
#
# The reload is Extensions.loadUnpacked over CDP,
# i.e. exactly the chrome://extensions Reload button, with the browser and its
# windows left alone (which matters over X11 forwarding, where restarting the
# browser is the expensive part). It is NOT chrome.runtime.reload(), which
# unloads an extension permanently (no service-worker target, every extension
# page ERR_BLOCKED_BY_CLIENT) until Chrome restarts.
#
# Re-running the script still works and is a full restart. It no longer wipes
# the profile: the wipe only ever existed because Chrome caches the extension's
# service worker in the user-data-dir and reuses it across restarts even with
# the manifest version bumped, and a CDP-loaded extension does not survive a
# restart at all - every launch installs it fresh from disk.
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# Not chrome's default 9222, deliberately: that port is the one an `ssh -R`
# tunnel from a laptop lands on, and sharing it is how an agent ends up
# driving someone else's browser (see the in-use check below).
PORT=${PORT:-9333}
DATA=${DATA:-/tmp/smartzoom-chrome}
PIDFILE=$DATA/.launcher.pid
DISPFILE=$DATA/.display

# Kill by pid, not `pkill -f`: the pattern would match this script's own cmdline.
stop() {
	[ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null || true
	rm -f "$PIDFILE" "$DISPFILE"
}

# Everything is keyed on DATA, so a second run with the same DATA kills the
# first - that IS the reload. The bad case is a HEADLESS run killing a HEADED
# session someone is working in, which is invisible from the far end of an ssh
# connection: the window just vanishes. So refuse when the running instance is
# attached to a display this run is not, unless FORCE=1 (or `stop`, which is an
# explicit request). Use a different DATA to run two side by side.
# Read back what the running instance recorded at launch. NOT from
# /proc/<pid>/environ: chrome scrubs its own environment block, so DISPLAY is
# simply not there to read (measured - a browser plainly running on :97 reports
# nothing), and the guard silently passed every time.
running_display() {
	[ -f "$PIDFILE" ] || return 1
	pid=$(cat "$PIDFILE")
	[ -d "/proc/$pid" ] || return 1
	cat "$DISPFILE" 2>/dev/null || echo ""
}

guarded_stop() {
	old=$(running_display) || { stop; return; }
	if [ -n "$old" ] && [ "$old" != "$DISPLAY" ]; then
		echo "refusing to kill the browser already running on DISPLAY=$old" >&2
		echo "  (this run has DISPLAY=${DISPLAY:-<none>}). FORCE=1 to kill it anyway," >&2
		echo "  DATA=/tmp/other to run a second one alongside, or 'stop' to end it." >&2
		[ -n "$FORCE" ] || exit 1
	fi
	stop
}

[ "$1" = "stop" ] && { stop; echo "stopped"; exit 0; }

# `<id><tab><path>` for our extension in the browser on $PORT, non-zero if it has
# none. The PATH is the interesting half: it says which machine that browser is
# on, which is the one thing a CDP client cannot see for itself.
ext_check() { PORT=$PORT node "$ROOT/tools/ext-load.js" --check 2>/dev/null; }
ext_path_is_ours() { [ "$1" = "$ROOT" ] || [ "$1" = "$ROOT/" ]; }

# The chrome://extensions Reload button, without the page or the mouse. Open
# http(s) tabs are reloaded with it, to pick up the new content scripts.
if [ "$1" = "reload" ]; then
	# Refuse a tunnelled browser. Extensions.loadUnpacked takes a path, and it is
	# resolved on the BROWSER's filesystem - so reloading the laptop's chrome from
	# here hands it this VM's path, which does not exist over there. Chrome answers
	# that with an error or, worse, whatever happens to sit at the same path,
	# neither of which is the edit you wanted to pick up.
	if found=$(ext_check) && ! ext_path_is_ours "${found#*	}"; then
		echo "refusing to reload: that browser loaded the extension from" >&2
		echo "  ${found#*	}" >&2
		echo "  not $ROOT - so it is running on another machine (the ssh -R tunnel)," >&2
		echo "  and the path this would send it is meaningless there." >&2
		echo "  Run 'dev-browser.sh reload' on THAT machine instead; 'status' confirms which is which." >&2
		exit 1
	fi
	ID=$(PORT=$PORT node "$ROOT/tools/ext-load.js") || exit 1
	echo "reloaded: chrome-extension://$ID (manual reload)"
	echo "          open tabs reloaded"
	exit 0
fi

# `status` answers the only question that matters when one fixed port serves two
# devices: WHICH browser is the MCP talking to right now. On the laptop the port
# is an `ssh -R` tunnel to chrome over there; on the phone it is a headed chrome
# here. Both look identical to a client, so ask the browser itself - and ask it
# for the extension's PATH, not just whether one is loaded: the laptop has the
# extension too, loaded from its own checkout, so "no extension" was never the
# tunnelled signal. A path that is not this repo is.
if [ "$1" = "status" ]; then
	echo "port:  $PORT"
	if own=$(running_display); then
		[ -n "$own" ] && where="headed on DISPLAY=$own" || where="headless"
		echo "local: dev-browser running (pid $(cat "$PIDFILE"), $where)"
	else
		echo "local: no dev-browser instance"
	fi
	ss -ltnpH "sport = :$PORT" 2>/dev/null | sed 's/^/sock:  /'
	ver=$(curl -s --max-time 3 "http://localhost:$PORT/json/version" 2>/dev/null || true)
	if [ -z "$ver" ]; then
		echo "cdp:   nothing answering on $PORT"
		exit 1
	fi
	echo "cdp:   $(printf %s "$ver" | sed -n 's/.*"Browser": "\([^"]*\)".*/\1/p')"
	if found=$(ext_check); then
		ID=${found%%	*}
		EXT_PATH=${found#*	}
		if ext_path_is_ours "$EXT_PATH"; then
			echo "ext:   loaded ($ID) from this repo -> the browser on THIS machine"
		else
			echo "ext:   loaded ($ID) from $EXT_PATH -> a tunnelled browser (your laptop), its own checkout"
		fi
	else
		echo "ext:   NOT loaded -> no extension of ours in this browser, or it is off"
	fi
	exit 0
fi

# Stable Chrome, not playwright's build: this is a browser a human sits in
# front of, and playwright's carries "Chrome for Testing" branding. It can be
# stable now because the extension arrives over CDP (tools/ext-load.js) rather
# than through --load-extension, which stable ignores. Falls back to
# playwright's chromium when there is no google-chrome; CHROME_BIN overrides.
CHROME=$CHROME_BIN
[ -n "$CHROME" ] || CHROME=$(command -v google-chrome || true)
[ -n "$CHROME" ] || CHROME=$(ls -d "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux64/chrome 2>/dev/null | tail -1)
[ -x "$CHROME" ] || { echo "no chrome - install google-chrome, or: npx playwright install chromium" >&2; exit 1; }

mkdir -p "$DATA"
guarded_stop
sleep 1
# The profile is kept across runs now (settings, history, logins). CLEAN=1 is
# the way back to a genuine first run.
[ -n "$CLEAN" ] && rm -rf "$DATA" && mkdir -p "$DATA"

# Refuse a port someone else is already listening on, because chrome does NOT
# fail loudly enough to notice. With 127.0.0.1:9222 taken it logs one
# `bind() failed: Address already in use` and then binds [::1]:9222 instead
# (measured), so `localhost:9222` reaches one of two different browsers
# depending on the resolver - and the readiness probe below, finding an
# extension on the OTHER one, reports success. The case that matters is an
# `ssh -R 9222:localhost:9222` tunnel putting a laptop's chrome on this box:
# an agent launching here would silently drive that browser instead.
# Our own previous instance is already gone by this point (guarded_stop above),
# but the kernel may need a moment to release the socket.
for _ in 1 2 3 4 5 6; do
	ss -ltnH "sport = :$PORT" 2>/dev/null | grep -q . || break
	sleep 0.5
done
if ss -ltnH "sport = :$PORT" 2>/dev/null | grep -q .; then
	echo "port $PORT is already in use by something else:" >&2
	ss -ltnpH "sport = :$PORT" 2>/dev/null | sed 's/^/  /' >&2
	echo "  an ssh -R tunnel or another browser holds it. Use PORT=9334 (or free it)." >&2
	echo "  chrome would otherwise bind the other IP stack and you would not notice." >&2
	exit 1
fi

if [ -n "$DISPLAY" ]; then
	MODE="headed on DISPLAY=$DISPLAY"
	# Chrome's own default window is small, and --start-maximized does NOTHING
	# here: maximising is a window-manager operation and an X11-forwarded
	# session (Termux:X11, plain `ssh -Y`) normally has no WM - measured on a
	# 1920x1200 display, 945x1180 both with and without the flag, against an
	# exact 1536x960 from --window-size. So size it explicitly, filling the
	# display (there is no WM to maximise it, and no titlebar taking space
	# either). WINDOW=1536,960 overrides; WINDOW= leaves chrome's own default.
	if command -v xdpyinfo >/dev/null 2>&1; then
		dim=$(xdpyinfo 2>/dev/null | awk '/dimensions:/{print $2; exit}')
		SCRW=${dim%x*}
		SCRH=${dim#*x}
	fi
	case "$SCRW$SCRH" in *[!0-9]* | "") SCRW= SCRH= ;; esac
	if [ -z "${WINDOW+set}" ] && [ -n "$SCRW" ]; then
		WINDOW=$SCRW,$SCRH
	fi
	if [ -n "$WINDOW" ]; then
		set -- --window-size="$WINDOW" "$@"
		if [ -n "$SCRW" ]; then
			set -- --window-position=$(((SCRW - ${WINDOW%,*}) / 2)),$(((SCRH - ${WINDOW#*,}) / 2)) "$@"
		fi
		MODE="$MODE, window $WINDOW"
	fi
else
	set -- --headless=new "$@"
	MODE="headless (no DISPLAY)"
	# Loud, because the fallback is silent otherwise and the symptom is just
	# "no window appeared" - which is what an ssh session that dropped X11
	# forwarding looks like too. Reconnect with -Y and check with xdpyinfo.
	echo "warning: no DISPLAY, running headless - no window will appear." >&2
	echo "         for a window: ssh -Y -C <host>, verify with 'xdpyinfo | head -3', re-run here." >&2
fi

# Opens a content-heavy page to zoom around in (content scripts only run on
# http/https, so not the new-tab page). `URL=` (empty) starts on the new-tab
# page instead, `URL=...` elsewhere - hence ${URL-default} rather than
# ${URL:-default}, so an empty value is a deliberate choice.
# Opened AFTER the extension loads (below), not on chrome's command line: a tab
# that loads before Extensions.loadUnpacked never gets the content scripts
# (measured - zoom.js absent until the page is reloaded), so neither double-click
# nor the context menu entry would do anything in it.
URL=${URL-https://en.wikipedia.org/wiki/Zoom_lens}

"$CHROME" --remote-debugging-port="$PORT" --user-data-dir="$DATA" \
	--no-first-run --no-default-browser-check \
	"$@" >"$DATA/chrome.log" 2>&1 &
echo $! >"$PIDFILE"
printf %s "$DISPLAY" >"$DISPFILE"

# No --load-extension (stable Chrome ignores it): install over CDP once the
# debug port answers. A CDP-loaded extension is gone after a restart, so this
# runs every launch - which is also what makes a stale service worker
# impossible and the old profile wipe unnecessary.
i=0
while [ $i -lt 60 ]; do
	curl -s --max-time 2 "http://localhost:$PORT/json/version" >/dev/null 2>&1 && break
	i=$((i + 1))
	sleep 0.5
done
ID=$(PORT=$PORT node "$ROOT/tools/ext-load.js" 2>&1) || {
	echo "$ID" | sed 's/^/  /' >&2
	ID=
}

if [ -z "$ID" ]; then
	# A dead X connection lands here too, and "extension did not load" is a
	# misleading way to say it, so name the real cause when the log shows it.
	if grep -q "Missing X server" "$DATA/chrome.log" 2>/dev/null; then
		echo "DISPLAY=$DISPLAY is set but unreachable - chrome could not open it." >&2
		echo "check with 'xdpyinfo | head -3'; if that fails, reconnect with ssh -Y" >&2
		echo "(and on the client: install xauth, keep the X server app foregrounded)." >&2
	else
		echo "extension did not load - see $DATA/chrome.log" >&2
	fi
	exit 1
fi

[ -n "$URL" ] && curl -s --max-time 5 -X PUT "http://localhost:$PORT/json/new?$URL" >/dev/null

echo "mode:     $MODE"
echo "cdp:      http://localhost:$PORT"
echo "ext:      chrome-extension://$ID  (popup: /popup.html)"

if [ "$WATCH" = "0" ]; then
	echo "stop:     ./tools/dev-browser.sh stop   (not watching, this shell returns)"
	exit 0
fi

# Stay in the foreground and reload when a watched file changes (the directory
# watcher is in tools/ext-load.js). It exits by itself when the browser
# does, so the stop below runs either way. WATCH=0 keeps the old
# fire-and-forget behaviour, for an agent that wants its shell back.
trap 'echo; stop; echo "stopped"; exit 0' INT TERM HUP

CHROME_PID=$(cat "$PIDFILE") PORT=$PORT node "$ROOT/tools/ext-load.js" --watch || true
stop

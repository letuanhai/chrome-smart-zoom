#!/usr/bin/env node
// Install (or reload) this repo as an unpacked extension in the running
// dev browser, over CDP. Prints the extension id.
//
// This replaces --load-extension, which stable Chrome silently ignores -
// headless AND headed, with or without
// --disable-features=DisableLoadExtensionCommandLineSwitch (measured on 151:
// the extension is simply absent from chrome://extensions, and only
// playwright's build honours the flag). Extensions.loadUnpacked works on
// stable, needs no flag, and hands back the SAME path-derived id, so the
// profile's Local Extension Settings keep matching.
//
// Called a second time on an already-loaded path it IS the chrome://extensions
// Reload button: it re-reads the service worker and the declared content
// scripts - the two things a browser restart alone does NOT pick up - and
// leaves chrome.storage.local intact (all three verified).
//
// A CDP-loaded extension does not survive a browser restart, so dev-browser.sh
// runs this at every launch; that is also why no stale worker can ever
// outlive one.
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const port = process.env.PORT || 9333;
const root = path.resolve(__dirname, "..");

// --check asks whether THIS extension is installed there - by path when the
// browser is on this box, else by manifest name - and prints `<id>\t<path>`, for
// dev-browser.sh's `status`. Asking the extension REGISTRY rather than looking
// for a service-worker target in /json/list is the point: the worker goes
// dormant after ~30s idle, and a missing target then reads as "not loaded".
const mode = process.argv[2];

// The files only an extension reload picks up (the popup is live on reopen).
// Grouped by directory because that is what gets watched.
const WATCHED = {
	".": ["manifest.json", "background.js"],
	js: ["zoom.js", "inject.js"],
};

async function loadUnpacked() {
	// close() on a connectOverCDP browser disconnects, it does not kill chrome.
	const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`, { timeout: 15000 });
	try {
		const session = await browser.newBrowserCDPSession();
		// Twice, deliberately. Installing an extension the profile has seen
		// before re-uses Chrome's cached copy of the service-worker script, so a
		// first load into a fresh browser can still come up running yesterday's
		// service worker (measured: file reverted, worker still answering with the old
		// global). Only a load of an ALREADY-loaded extension - the Reload
		// button's path - re-reads it, so the second call makes the first honest.
		await session.send("Extensions.loadUnpacked", { path: root });
		const { id } = await session.send("Extensions.loadUnpacked", { path: root });
		// A reload orphans the content scripts in every open tab, so reload the
		// pages they run on (http/https) to inject the new ones. Not waiting for
		// load: a slow or hung page must not stall the watcher.
		const pages = browser.contexts().flatMap((c) => c.pages()).filter((p) => /^https?:/.test(p.url()));
		await Promise.all(pages.map((p) => p.reload({ waitUntil: "commit" }).catch(() => {})));
		return id;
	} finally {
		await browser.close();
	}
}

// Watch the DIRECTORIES, not the files: an editor that saves atomically
// (write temp + rename, which vim and most others do) leaves a per-file watch
// bound to the old inode, silently never firing again. A directory watch
// reports the name, so it survives the swap.
//
// Caveat this cannot fix: the repo is on NFS4, and inotify only ever sees
// changes made by THIS client - measured against a file on the same server
// written from a second NFS client, no event in 72s (and no mtime change
// either, this mount being acregmin/acregmax=1800, so polling would have been
// just as blind). Edit on this box, or run `dev-browser.sh reload` by hand.
function watch() {
	const chromePid = Number(process.env.CHROME_PID) || 0;
	let timer = null;
	let running = false;
	const changedFiles = new Set();

	const watched = Object.entries(WATCHED).flatMap(([dir, names]) =>
		names.map((n) => (dir === "." ? n : path.join(dir, n))));
	console.log(`watch:    ${watched.join(", ")}`);
	console.log("          each reload reports the changed file paths");
	console.log("          Ctrl-C to stop the browser and exit");

	const reload = async () => {
		if (running) return;
		const files = [...changedFiles].join(", ");
		changedFiles.clear();
		running = true;
		try {
			const id = await loadUnpacked();
			log(`reloaded ${id} and open tabs (changed: ${files})`);
		} catch (err) {
			log(`reload failed (changed: ${files}): ${err.message}`);
		}
		running = false;
		if (changedFiles.size) schedule();
	};

	// One save can produce several events (and a rename plus a change); coalesce.
	const schedule = () => {
		clearTimeout(timer);
		timer = setTimeout(reload, 300);
	};

	for (const [dir, names] of Object.entries(WATCHED)) {
		fs.watch(path.join(root, dir), (_event, name) => {
			if (names.includes(name)) {
				changedFiles.add(path.join(dir, name));
				schedule();
			}
		});
	}

	// Nothing to watch for if the browser is gone: exit and let dev-browser.sh
	// clean up. Cheap local-process check, no CDP round trip.
	if (chromePid) {
		setInterval(() => {
			try {
				process.kill(chromePid, 0);
			} catch {
				log("browser exited");
				process.exit(0);
			}
		}, 1000).unref();
	}
}

const log = (msg) => console.log(`${new Date().toTimeString().slice(0, 8)} ${msg}`);

(async () => {
	if (mode === "--watch") return watch();

	if (mode === "--check") {
		const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`, { timeout: 15000 });
		const session = await browser.newBrowserCDPSession();
		const { extensions } = await session.send("Extensions.getExtensions");
		// Path equality alone answers the WRONG question on a tunnelled browser:
		// the laptop loads the extension from its OWN checkout, so its path never
		// matches this box's and a plainly-loaded extension read as "NOT loaded".
		// So fall back to the manifest name, and print the path for `status` to
		// tell the two cases apart.
		const { name } = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"));
		const mine =
			extensions.find((e) => e.path === root || e.path === root + "/") ||
			extensions.find((e) => e.name === name);
		await browser.close();
		if (!mine) process.exit(1);
		console.log(`${mine.id}\t${mine.path}`);
		return;
	}

	console.log(await loadUnpacked());
})().catch((err) => {
	console.error(`ext-load: ${err.message}`);
	process.exit(1);
});

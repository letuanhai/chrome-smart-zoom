# Chrome Smart Zoom

Bring MacOS 2 fingers double-tap to Chromium browsers on all OSes.  
Double right-click to zoom-in, double right-click again or ESC to zoom-out.  
Settings popup: switch the trigger to middle-click or none, and optionally add a "zoom in / out" entry to the context menu.






Credit:  
[zoom.js](http://lab.hakim.se/zoom-js) by [Hakim El Hattab](http://hakim.se)  
[Icon by Dryicons](https://dryicons.com/free-icons/double-finger)
## Development

`npm install`, then `npm run dev` (from an `ssh -Y` session for a window over X11 forwarding) launches Chrome with the extension loaded over CDP on port 9333 and reloads it when `manifest.json`, `background.js` or `js/*.js` change. `./tools/dev-browser.sh status|reload|stop` from another shell. See the header of `tools/dev-browser.sh` for options.

`npm run package` writes the store upload to `dist/smartzoom-<version>.zip` (runtime files only).

// Default settings
const DEFAULT_TRIGGER = 'right';
const DEFAULT_PADDING = 20;
let zoomPadding = DEFAULT_PADDING;

// Double-click handler factory
function makeDoubleClickHandler(handler) {
    var timeout = 0, clicked = false;
    return function (e) {
        if (clicked) {
            // Prevent default only on double click (prevents context menu for right-click)
            e.preventDefault();
            clearTimeout(timeout);
            clicked = false;
            return handler.apply(this, arguments);
        }
        else {
            clicked = true;
            timeout = setTimeout(function () {
                clicked = false;
            }, 300);
        }
    };
}

// Initialize event listeners based on settings
function init() {
    chrome.storage.sync.get({ trigger: DEFAULT_TRIGGER, padding: DEFAULT_PADDING }, function(items) {
        zoomPadding = typeof items.padding === 'number' ? items.padding : DEFAULT_PADDING;
        setupEventListeners(items.trigger);
    });
}

function setupEventListeners(trigger) {
    const body = document.querySelector('body');
    
    if (trigger === 'middle') {
        // Use auxclick for middle mouse button (button === 1)
        body.addEventListener('auxclick', makeDoubleClickHandler(function (event) {
            if (event.button === 1) { // Middle mouse button
                zoom.to({ element: event.target, padding: zoomPadding });
            }
        }));
    } else {
        // Use mousedown for right mouse button (default)
        // Using mousedown instead of contextmenu to prevent menu interference
        body.addEventListener('mousedown', makeDoubleClickHandler(function (event) {
            if (event.button === 2) { // Right mouse button
                zoom.to({ element: event.target, padding: zoomPadding });
            }
        }));
    }
}

// Initialize on load
init();

// Listen for settings changes from popup
chrome.storage.onChanged.addListener(function(changes, area) {
    if (area === 'sync') {
        if (changes.trigger) {
            // Reload page to apply new trigger setting
            window.location.reload();
        }
        if (changes.padding) {
            // Update padding immediately without reload
            zoomPadding = changes.padding.newValue;
        }
    }
});

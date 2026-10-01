const MENU_ID = 'smartzoom-toggle';

// Add or remove the context menu entry to match the setting
function syncContextMenu() {
    chrome.storage.sync.get({ contextMenu: false }, function (items) {
        chrome.contextMenus.removeAll(function () {
            if (items.contextMenu) {
                chrome.contextMenus.create({
                    id: MENU_ID,
                    title: 'SmartZoom: zoom in / out',
                    contexts: ['all'],
                    documentUrlPatterns: ['http://*/*', 'https://*/*']
                });
            }
        });
    });
}

chrome.runtime.onInstalled.addListener(syncContextMenu);

chrome.storage.onChanged.addListener(function (changes, area) {
    if (area === 'sync' && changes.contextMenu) {
        syncContextMenu();
    }
});

chrome.contextMenus.onClicked.addListener(function (info, tab) {
    if (info.menuItemId === MENU_ID) {
        // Fails if the content script isn't there (e.g. tab opened before install); nothing to zoom then
        chrome.tabs.sendMessage(tab.id, 'toggle-zoom', { frameId: info.frameId }).catch(function () {});
    }
});

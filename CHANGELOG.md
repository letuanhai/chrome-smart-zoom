# Changelog

All notable changes to this project will be documented in this file.

## [1.2.0] - 2026-10-01

### Added
- Optional "SmartZoom: zoom in / out" context menu entry (off by default)
- "None" zoom trigger to disable mouse double-click zooming

### Changed
- Manifest description now describes the zoom gesture directly
- New store screenshots and description (1.1.0 was rejected by the Chrome Web Store for unrelated media)

## [1.1.0] - 2026-04-29

### Added
- Configurable zoom trigger setting (right-click or middle-click) via popup
- Configurable zoom padding setting via popup
- Configurable transition duration setting
- Added popup for extension settings

### Changed
- Reverted to use contextmenu event for right-click detection
- Shortened manifest description for Chrome Web Store publishing

### Removed
- Removed panning functionality

## [1.0.0] - Initial Release

### Added
- Initial SmartZoom extension release
- Double-click zoom functionality (2-finger double-tap equivalent)
- Support for double right-click or double middle-click to zoom
- ESC key to zoom out

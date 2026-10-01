#!/bin/sh
# Build the Chrome Web Store zip into dist/. Allowlist of runtime files, so
# dev-only files (tools/, store/, package.json, node_modules/) never ship.
set -e
cd "$(dirname "$0")/.." # repo root = extension root

VERSION=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' manifest.json)
OUT="dist/smartzoom-${VERSION}.zip"
mkdir -p dist
rm -f "$OUT"
zip -qr "$OUT" manifest.json background.js popup.html popup.js js images
echo "Wrote $OUT ($(du -h "$OUT" | cut -f1))"

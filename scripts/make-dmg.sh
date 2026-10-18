#!/bin/bash
# Builds dist/Linnet-<version>.dmg: the app plus an Applications shortcut on a styled background. No Finder windows are opened.
# Usage: ./scripts/make-dmg.sh [--no-build]
set -euo pipefail
cd "$(dirname "$0")/.."
[ "${1:-}" = "--no-build" ] || ./build-app.sh
APP=dist/Linnet.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT="dist/Linnet-$VERSION.dmg"

if [ ! -x .tools/venv/bin/dmgbuild ]; then
  mkdir -p .tools && python3 -m venv .tools/venv && .tools/venv/bin/pip install --quiet dmgbuild
fi
swiftc -O -o /tmp/make-dmg-bg scripts/make-dmg-background.swift
/tmp/make-dmg-bg Branding/dmg-background
tiffutil -cathidpicheck Branding/dmg-background.png Branding/dmg-background@2x.png -out Branding/dmg-background.tiff

rm -f "$OUT"
.tools/venv/bin/dmgbuild -s scripts/dmg-settings.py -D app="$APP" "Linnet" "$OUT"
echo "Built $OUT ($(du -h "$OUT" | cut -f1))"

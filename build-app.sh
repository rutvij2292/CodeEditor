#!/bin/bash
# Builds a release Kode.app in ./dist (grammar query bundles, fonts and the icon go in Contents/Resources).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --build-system native
BIN_DIR=$(swift build -c release --build-system native --show-bin-path)

NAME=Kode
APP="dist/$NAME.app"
VERSION="0.$(git rev-list --count HEAD 2>/dev/null || echo 1)"
rm -rf dist/CodeEditor.app dist/Linnet.app "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CodeEditor" "$APP/Contents/MacOS/$NAME"
[ -f Branding/AppIcon.icns ] || ./scripts/make-icns.sh
cp Branding/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R "$BIN_DIR"/*.bundle "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/Fonts"
cp Fonts/*.ttf Fonts/OFL.txt "$APP/Contents/Resources/Fonts/"
# PHP built-in stubs for the native PHP engine (JetBrains phpstorm-stubs, Apache-2.0; LICENSE + SOURCE.txt travel with them).
# Regenerate with scripts/make-php-stubs.py. Read lazily at run time, never at launch.
[ -f PhpStubs/index.txt ] || { echo "PhpStubs/ missing: run scripts/make-php-stubs.py" >&2; exit 1; }
cp -R PhpStubs "$APP/Contents/Resources/PhpStubs"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>com.teccel.CodeEditor</string>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Teccel Software. Bundled font: JetBrains Mono (SIL OFL 1.1). PHP stubs: JetBrains phpstorm-stubs (Apache 2.0).</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Project folder or source file</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array><string>public.folder</string><string>public.text</string><string>public.source-code</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"

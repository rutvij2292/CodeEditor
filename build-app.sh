#!/bin/bash
# Builds a release CodeEditor.app in ./dist (grammar query bundles go in Contents/Resources).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --build-system native
BIN_DIR=$(swift build -c release --build-system native --show-bin-path)

APP=dist/CodeEditor.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CodeEditor" "$APP/Contents/MacOS/CodeEditor"
cp -R "$BIN_DIR"/*.bundle "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/Fonts"
cp Fonts/*.ttf Fonts/OFL.txt "$APP/Contents/Resources/Fonts/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>CodeEditor</string>
    <key>CFBundleIdentifier</key><string>com.teccel.CodeEditor</string>
    <key>CFBundleName</key><string>CodeEditor</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
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

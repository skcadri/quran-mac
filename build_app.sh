#!/bin/bash
# Build Mushaf and package it into a double-clickable .app bundle.
set -e
cd "$(dirname "$0")"

CONFIG="${1:-release}"
echo "Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN=$(swift build -c "$CONFIG" --show-bin-path)/Mushaf
APP="$PWD/Mushaf.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Mushaf"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Mushaf</string>
  <key>CFBundleDisplayName</key><string>Mushaf</string>
  <key>CFBundleIdentifier</key><string>com.sohaib.mushaf</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>Mushaf</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.reference</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so the window server / network behave predictably.
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "Built: $APP"

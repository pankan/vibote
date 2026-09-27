#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
xcrun swiftc -O -swift-version 5 -module-cache-path "$PWD/.build/module-cache" Sources/*.swift -o .build/Vibote
APP="$PWD/build/Vibote.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/Vibote "$APP/Contents/MacOS/Vibote"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
# Give changed artwork a new resource name so macOS does not reuse its old icon.
ICON_HASH=$(shasum -a 256 Resources/AppIcon.icns | cut -c 1-12)
ICON_NAME="AppIcon-$ICON_HASH"
cp Resources/AppIcon.icns "$APP/Contents/Resources/$ICON_NAME.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $ICON_NAME" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
touch "$APP"
printf 'Built %s\n' "$APP"

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
for ARCH in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 -target "$ARCH-apple-macos14.0" -module-cache-path "$PWD/.build/module-cache" Sources/*.swift -o ".build/Vibote-$ARCH"
done
xcrun lipo -create .build/Vibote-arm64 .build/Vibote-x86_64 -output .build/Vibote
APP="$PWD/build/Vibote.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/Vibote "$APP/Contents/MacOS/Vibote"
cp Info.plist "$APP/Contents/Info.plist"
python3 scripts/version.py --stamp "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
./scripts/build-mic.sh
rm -rf "$APP/Contents/Resources/ViboteMic.driver"
cp -R build/ViboteMic.driver "$APP/Contents/Resources/ViboteMic.driver"
cp scripts/install-mic-from-app.sh "$APP/Contents/Resources/install-mic-from-app.sh"
# Give changed artwork a new resource name so macOS does not reuse its old icon.
ICON_HASH=$(shasum -a 256 Resources/AppIcon.icns | cut -c 1-12)
ICON_NAME="AppIcon-$ICON_HASH"
cp Resources/AppIcon.icns "$APP/Contents/Resources/$ICON_NAME.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $ICON_NAME" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
touch "$APP"
printf 'Built %s\n' "$APP"

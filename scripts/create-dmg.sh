#!/bin/bash
# Build a universal app and package the website/GitHub download.
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
  "") ./scripts/build.sh ;;
  --skip-build) test -d build/Vibote.app || { echo "Build Vibote first." >&2; exit 1; } ;;
  *) echo "Usage: $0 [--skip-build]" >&2; exit 1 ;;
esac
python3 scripts/check-bundle.py
STAGING="$PWD/.build/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING/.Installation"
/usr/bin/ditto build/Vibote.app "$STAGING/Vibote.app"
ln -s /Applications "$STAGING/Applications"
cp LICENSE "$STAGING/.Installation/License.txt"
cat > "$STAGING/.Installation/Install Vibote.txt" <<'EOF'
Install Vibote

1. Drag Vibote.app onto Applications.
2. Eject this disk image and open Vibote from Applications.
3. Pair your T6 remote in System Settings > Bluetooth.
4. Follow Vibote's Permissions panel.

For AI voice apps, select AI voice app in Vibote's Voice panel and click
Install Vibote Mic. macOS asks for administrator approval and briefly
restarts audio. Choose Vibote Mic as your voice app's microphone.

Enable General > Start at login to open Vibote when you sign in.

This open-source build is not notarized. If macOS blocks it, open
System Settings > Privacy & Security and choose Open Anyway for Vibote.

Requires macOS 14 or later. Supports Apple silicon and Intel Macs.
Source: https://github.com/pankan/vibote
EOF
/usr/bin/codesign --verify --deep --strict "$STAGING/Vibote.app"
if [[ ! -x .build/dmg-tools/bin/dmgbuild ]]; then
  python3 -m venv .build/dmg-tools
  .build/dmg-tools/bin/python -m pip install 'dmgbuild==1.6.7'
fi
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path "$PWD/.build/module-cache" scripts/dmg-background.swift -o .build/dmg-background
.build/dmg-background "$PWD/.build/dmg-background.tiff"
.build/dmg-tools/bin/dmgbuild -D root="$PWD" -s scripts/dmg-settings.py Vibote "$PWD/build/Vibote.dmg"
/usr/bin/hdiutil verify "$PWD/build/Vibote.dmg"
VERSION=$(python3 scripts/version.py)
cp build/Vibote.dmg "build/Vibote-$VERSION.dmg"
(cd build && shasum -a 256 "Vibote-$VERSION.dmg" > "Vibote-$VERSION.dmg.sha256")
printf 'Created %s\n' "$PWD/build/Vibote-$VERSION.dmg"

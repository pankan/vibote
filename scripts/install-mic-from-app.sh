#!/bin/bash
# Invoked by Vibote with macOS administrator authorization. No developer tools needed.
set -euo pipefail
SOURCE="${1:?Missing bundled microphone driver}"
HAL="/Library/Audio/Plug-Ins/HAL"
[[ "$EUID" == 0 ]] || { echo "Administrator authorization is required." >&2; exit 1; }
[[ -f "$SOURCE/Contents/MacOS/ViboteMic" && -f "$SOURCE/Contents/Info.plist" ]] || { echo "Bundled microphone driver is missing." >&2; exit 1; }
/usr/bin/codesign --verify --strict "$SOURCE"
mkdir -p "$HAL"
STAGING=$(mktemp -d "$HAL/.ViboteMic.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
/usr/bin/ditto "$SOURCE" "$STAGING/ViboteMic.driver"
/usr/sbin/chown -R root:wheel "$STAGING/ViboteMic.driver"
/bin/chmod -R go-w "$STAGING/ViboteMic.driver"
rm -rf "$HAL/ViboteMic.driver" "$HAL/T6RemoteMic.driver"
mv "$STAGING/ViboteMic.driver" "$HAL/ViboteMic.driver"
/usr/bin/killall coreaudiod

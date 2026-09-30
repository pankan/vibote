#!/bin/bash
# Builds the Vibote Mic virtual audio device (Core Audio HAL plug-in).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$PWD/build/ViboteMic.driver"
rm -rf "$OUT"; mkdir -p "$OUT/Contents/MacOS"
xcrun clang -bundle -O2 -Wall -Wextra -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
  -framework CoreAudio -framework CoreFoundation Driver/ViboteMic.c -o "$OUT/Contents/MacOS/ViboteMic"
cp Driver/Info.plist "$OUT/Contents/Info.plist"
python3 scripts/version.py --stamp "$OUT/Contents/Info.plist"
codesign --force --sign - "$OUT"
printf 'Built %s\n' "$OUT"

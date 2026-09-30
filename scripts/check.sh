#!/bin/bash
# Run without optimization: Swift assert checks must remain enabled.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
for pair in 'ADPCM DecoderChecks' 'BatteryLevel BatteryLevelChecks' 'MicrophoneErrors MicrophoneErrorChecks'; do
  read -r source test <<< "$pair"
  xcrun swiftc -module-cache-path "$PWD/.build/module-cache" "Sources/$source.swift" "Tests/$test.swift" -o ".build/$test"
  ".build/$test"
done
xcrun clang -Wall -Wextra -framework CoreAudio -framework CoreFoundation Tests/DriverChecks.c -o .build/driver-checks
.build/driver-checks
for script in scripts/*.sh; do bash -n "$script"; done
python3 scripts/check-site.py
python3 scripts/version.py
node --check docs/site.js
plutil -lint Info.plist Driver/Info.plist
git diff --check

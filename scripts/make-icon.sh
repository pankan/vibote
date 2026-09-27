#!/bin/bash
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache Resources
xcrun swiftc -module-cache-path "$PWD/.build/module-cache" scripts/make-icon.swift -o .build/make-icon
rm -rf .build/AppIcon.iconset
.build/make-icon .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
printf 'Wrote Resources/AppIcon.icns\n'

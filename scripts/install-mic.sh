#!/bin/bash
# Installs (or with --uninstall removes) Vibote Mic. Needs an administrator password.
# Restarting coreaudiod briefly interrupts all audio on the Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="/Library/Audio/Plug-Ins/HAL/ViboteMic.driver"
OLD="/Library/Audio/Plug-Ins/HAL/T6RemoteMic.driver" # pre-rename install
if [[ "${1:-}" == "--uninstall" ]]; then
  sudo rm -rf "$DEST" "$OLD"
else
  ./scripts/build-mic.sh
  sudo rm -rf "$DEST" "$OLD"
  sudo cp -R build/ViboteMic.driver "$DEST"
fi
sudo killall coreaudiod
echo "Done. “Vibote Mic” should now appear as a microphone in System Settings → Sound → Input."

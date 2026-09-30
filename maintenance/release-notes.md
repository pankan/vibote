Vibote turns a T6 Bluetooth remote into a macOS shortcut and voice controller.

## Install

1. Download **Vibote.dmg**, open it, and drag Vibote into Applications.
2. Eject the disk image and open Vibote from Applications.
3. Pair the remote in System Settings → Bluetooth and follow Vibote's Permissions panel.
4. For AI voice apps, click **Install Vibote Mic** inside Vibote, then select Vibote Mic in your voice app. Administrator approval is required; audio restarts briefly.

Requires macOS 14 or later. Includes Apple silicon and Intel binaries.

This build is ad-hoc signed and **not notarized**. If macOS blocks opening it, use **System Settings → Privacy & Security → Open Anyway**. Do not disable Gatekeeper.

Both DMG filenames contain the same app. `Vibote.dmg` is the stable website download name; the versioned filename is useful for archives. `SHA256SUMS.txt` contains their checksums.

Only the documented T6 remote is supported initially. Firmware variants, on-device language availability, and third-party voice app behavior can differ. See the changelog and README for details.

User-reported testing: remote dictation, AI voice apps, in-app Vibote Mic installation, and start at login work on macOS 27 with an M3 Pro. Intel and macOS 14 runtime testing have not been completed. The release-readiness changes still need a final hardware smoke test.

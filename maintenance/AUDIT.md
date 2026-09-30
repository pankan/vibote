# Release-readiness audit — 30 September 2026

Scope: tracked source, reachable local Git history, build and DMG scripts, website, and accessible GitHub settings. This is an engineering review, not a penetration test or a guarantee of defect-free software.

## Fixed

- Removed a developer-machine Bluetooth peripheral UUID from discovery. Supported remotes are found by model name and scanning.
- Removed the unsafe CFString-to-raw-pointer conversion warning in Core Audio lookup.
- Replaced the obsolete BlackHole status message with Vibote Mic.
- Drained Homebrew output while Handy installation runs, avoiding a full-pipe deadlock, and blocked duplicate installs.
- Made driver ring samples atomic, aligned its property scratch buffer, validated null inputs and the complete audio format, and fixed timestamp catch-up after scheduling gaps. Added callback tests without installing the driver.
- Made the newest scroll-edge API conditional on the compiler so older Xcode toolchains can build the macOS 14 app.
- Cleaned the app bundle before rebuilding so obsolete resources cannot remain in a release.
- Added a single version source, fresh-build release packaging, draft release workflow, checksums, pinned Actions, CI, and Pages deployment.
- Replaced website download copies with a stable GitHub Releases link. Added contributor, privacy, security, changelog, and maintainer guidance.

## Repository inspection

A pattern scan of reachable text history found no matches for private keys, common GitHub/AWS tokens, or quoted credential assignments. Binary assets were not covered by that text scan. The removed peripheral UUID and old builds remain in earlier history; the UUID is a local Bluetooth identifier, not a credential. No history rewrite was performed.

The repository was private during the audit. Description, homepage, topics, squash-only merging, automatic merged-branch deletion, and read-only default Actions permissions were configured. Branch protection and private vulnerability reporting must be enabled after public visibility is approved; the current private plan does not provide them. The intended protection payload is checked in.

## Verification and limitations

- Swift checks cover decoder behavior, battery payload validation, and remote error messages.
- Driver checks cover format rejection, ring wraparound, consumed-sample silence, lock-free sample atomics on the test machine, and clock catch-up.
- Static checks cover local website links/anchors, JavaScript syntax, shell syntax, plist files, and version format.
- Both app and driver are built for arm64 and x86_64. This does not establish runtime support on Intel or every supported macOS version.
- The maintainer reports successful remote dictation, AI voice app use, in-app mic installation, and start at login on macOS 27 / M3 Pro before these audit changes. A final hardware smoke test of the new build remains necessary.
- Builds remain ad-hoc signed and not notarized. Installation instructions disclose this and use macOS Open Anyway, not system-wide Gatekeeper changes.
- The HAL driver remains a minimal implementation; stress testing under prolonged recording, multiple clients, sleep/wake, and different voice apps is recommended before claiming production-grade audio reliability.
- Remote product photography is user-supplied; this audit did not independently establish its licensing. Third-party names and photos should not be presented as project-owned MIT artwork.

## Publication sequence

Review and merge the preparation PR after CI passes. Confirm the new DMG with the physical remote. Then approve public visibility, enable protection/security reporting/Pages, tag the reviewed commit, inspect the generated draft release, and publish it. Do not announce a working download before the first release asset exists.

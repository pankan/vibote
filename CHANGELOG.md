# Changelog

## 0.1.1 — 2026-09-30

- Find paired remotes through their voice service as well as HID; remember verified remotes locally.
- Show bounded Bluetooth connection states and a Reconnect button.
- Allow reinstalling the bundled microphone driver from the app.

## 0.1.0 — Superseded by 0.1.1 (never published)

Initial public release candidate:

- T6 Bluetooth remote button mapping and hold-to-talk.
- Apple on-device transcription and optional AI voice app integrations.
- Bundled Vibote Mic installation from the app.
- Remote battery, voice level, permissions, and start-at-login controls.
- Universal macOS 14+ app and drag-to-Applications DMG.
- Open-source website, automated checks, and versioned release packaging.

Known limitations: only the documented T6 model is supported; firmware variants may differ. Battery level requires the remote to expose the BLE Battery service. Third-party integrations may change. Builds are not notarized; physical Intel and clean-machine testing must be recorded before publication.

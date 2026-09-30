# Security

Vibote is early software. Security fixes are maintained on `main` and released for the latest version only.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/pankan/vibote/security/advisories/new). Include the affected version, reproduction steps, impact, and a minimal example with personal information removed. Please do not publish exploit details in an issue. There is no guaranteed response time or bug bounty.

## Trust boundaries

Vibote can read supported remote inputs, send shortcuts, and type dictated text into the focused app when granted the corresponding macOS permissions. The optional Vibote Mic driver is installed into `/Library/Audio/Plug-Ins/HAL` with administrator approval and runs inside the system audio service. Only install builds from a source you trust.

The initial release is ad-hoc signed, not Apple notarized. Checksums detect a changed download; they do not independently establish publisher identity. Do not disable Gatekeeper system-wide to install Vibote.

On-device transcription explicitly requires Apple's on-device recognizer. Third-party voice apps have their own privacy policies. See [PRIVACY.md](PRIVACY.md).

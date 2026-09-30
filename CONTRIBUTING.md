# Contributing to Vibote

Small, focused contributions are welcome. Open an issue first for a new remote or a substantial feature, so we can agree on behavior before implementation.

## Development

Use macOS 14 or later, the Xcode command-line tools, Python 3, and Node.js (for the website syntax check). Clone the repository and create a branch. Run:

```sh
./scripts/check.sh
./scripts/build.sh
open build/Vibote.app
```

`check.sh` runs the decoder, battery, and microphone-error checks with assertions enabled, plus website, shell, and metadata checks. Building compiles both Apple silicon and Intel binaries. Hardware behavior needs a real remote; say explicitly what you tested.

For the static website, run `python3 -m http.server 8080 --directory docs`. Test a narrow and wide window, keyboard navigation, and reduced motion. Keep asset URLs relative so the site works under `/vibote/` on GitHub Pages.

## Pull requests

- Target `main`; explain the problem and the resulting behavior.
- Keep changes focused and add meaningful regression checks for logic changes.
- Do not commit binaries, recordings, personal diagnostics, credentials, or signing certificates.
- Never install the microphone driver automatically. Installation must remain an explicit user action with macOS administrator authorization.
- Document changes to permissions, local storage, or third-party app integrations.
- Treat contributors respectfully. Discuss the work, not the person; harassment is not welcome.

Contributions are provided under this repository's MIT license. Report vulnerabilities using [SECURITY.md](SECURITY.md), not a public issue.

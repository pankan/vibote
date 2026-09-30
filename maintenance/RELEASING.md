# Maintaining and releasing Vibote

## One-time GitHub setup

After reviewing the repository and its reachable history for private content, make it public. Never publish a signing key or personal recording. The current free private-repository plan does not support branch protection.

1. Merge the release-readiness changes and wait for **CI / Build and checks** to pass.
2. Set Settings → Pages → Source to **GitHub Actions**. The workflow publishes `docs/` at https://pankan.github.io/vibote/.
3. Apply `maintenance/branch-protection.json` to `main` using the GitHub API. It requires PRs, up-to-date passing checks, resolved conversations, and linear history; force pushes and deletion are blocked, including for admins. Zero required approvals lets a solo maintainer merge their own PR after checks pass.
4. Enable private vulnerability reporting, secret scanning and push protection where available. Set squash merge only and delete merged branches automatically.
5. Keep Actions workflow permissions read-only by default. Workflows request only the additional permissions they need. Dependabot proposes pinned Action updates monthly.

## Versioning

`VERSION` is the source of truth: `major.minor.patch`, initially `0.1.0`. Both the app and bundled driver are stamped during builds; bundle identifiers stay stable to preserve preferences and permissions. Update `VERSION` and `CHANGELOG.md` together in a PR. Use patch releases for fixes, minor releases for features, and reserve `1.0.0` for a stable supported experience.

## Publishing a release

1. Merge a version/changelog PR and ensure CI passed on `main`.
2. Run the Release workflow manually on `main` to rehearse packaging if desired; this only uploads an Actions artifact.
3. Create an annotated `v0.1.0` tag (replace the version for later releases) on that reviewed main commit and push that tag. The release workflow rejects mismatched versions or commits outside main.
4. GitHub builds a fresh universal app and styled DMG, computes checksums, and creates a **draft release**. It does not silently publish an untested binary.
5. Download the draft DMG and test it on a clean macOS account/machine: Gatekeeper opening, drag/install, Bluetooth pairing, reconnect/wake, permissions, button mapping, on-device dictation, optional driver install, a voice app, and start at login. Test Intel separately; cross-compilation does not prove runtime behavior.
6. Review release notes, replace the testing placeholder, and publish the draft. The website's stable link resolves to the latest non-prerelease release asset named `Vibote.dmg`.

The website's download link works only after the first release is published. Keep `Vibote.dmg`, `Vibote-VERSION.dmg`, and `SHA256SUMS.txt` attached. Do not overwrite a published version: fix forward with a new version. If packaging fails before creating a draft, fix the cause or rerun the failed job. If a draft already exists, inspect it rather than blindly rerunning release creation.

## Signing

Current builds are ad-hoc signed, without an Apple Developer ID or notarization. Be explicit about this in download instructions. Future signing requires an Apple Developer account, secure CI secrets, hardened runtime/entitlement testing, notarization, and stapling. Never commit certificates or credentials.

## Removing the app

Disable Start at login in Vibote, quit it, and delete `/Applications/Vibote.app`. If the optional driver was installed, developers can run `./scripts/install-mic.sh --uninstall` from a source checkout (administrator approval; audio restarts). Preferences and local diagnostics can be removed separately. A user-facing driver uninstall button is a future improvement.

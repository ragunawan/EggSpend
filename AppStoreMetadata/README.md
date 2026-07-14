# App Store Metadata

Copy-ready text for the App Store Connect listing, one locale folder per language (currently only `en-US`).

- `en-US/description.txt` — the full App Store description (product page body text).
- `en-US/whats_new.txt` — "What's New in This Version" release notes for the next submission.

Paste these directly into the corresponding App Store Connect fields when preparing a release. `whats_new.txt` should be rewritten each release to describe only what changed since the previous submitted build — check `CHANGELOG.md`'s `Unreleased` section and `git log` since the last `MARKETING_VERSION` bump (`EggSpend.xcodeproj/project.pbxproj`) for the source material. `description.txt` only needs updating when the app's overall feature set changes enough to make the listing stale.

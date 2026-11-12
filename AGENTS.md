# Project Instructions

## Local System Installation

- After completing and verifying code updates, automatically replace `/Applications/CodexMeter.app` with the verified local build and restart it. This is standing user authorization; do not ask for confirmation again for each update.
- Preserve the existing bundle identifier, preferences and usage data. Keep a local backup of the previous application, and verify the installed package before reporting success.
- Store historical application backups as verified ZIP archives, not additional runnable `.app` copies or registered applications.
- Local installation does not authorize GitHub synchronization, public releases or Homebrew publishing.

## Reusable UI Preview Identity

- Reuse the existing authorized preview at `/private/tmp/codexmeter-unified-hud-qa/dashboard/CodexMeter.app` with bundle identifier `io.github.codexmeter.unified-hud-qa.dashboard` for every UI test. Keep both values fixed; never create round-specific application paths or bundle identifiers.
- Update that preview in place, preserving its isolated preferences and authorization. Change language, appearance and fixture flags within this same application. Use `scripts/preview-app.sh` for preparation and launch.
- Stop the preview before replacing it and after testing. Resolve executable paths before comparing them: `/tmp` and `/private/tmp` may identify the same application. Verify that no preview process remains; do not launch duplicate instances with `open -n`.
- Preserve baseline evidence as logs, screenshots or verified archives. Unregister only obsolete application paths when cleaning up; do not reset global Launch Services or privacy permissions, and do not reset the retained preview's authorization.

## GitHub Synchronization and Homebrew Publishing

- Synchronize this project to GitHub only when the user explicitly gives a manual command to do so.
- Publish or update the Homebrew tap/cask only when the user explicitly gives a manual command to do so.
- Authorization for an earlier release does not authorize subsequent synchronization or publishing. A GitHub synchronization request alone does not authorize a Homebrew release.
- Completing development, fixes, reviews, version changes, tests, builds, or local packaging must not automatically trigger a push, tag publication, GitHub release, public artifact upload, or Homebrew publication.
- Prepare and verify the requested work locally. Without the corresponding explicit user command, leave remote repositories and published releases unchanged.

## UI Design

- Follow [design.md](design.md) for UI-only changes and visual verification. Preserve existing features, preferences and data behavior.

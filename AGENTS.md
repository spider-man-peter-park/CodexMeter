# Project Instructions

## GitHub Synchronization and Homebrew Publishing

- Synchronize this project to GitHub only when the user explicitly gives a manual command to do so.
- Publish or update the Homebrew tap/cask only when the user explicitly gives a manual command to do so.
- Authorization for an earlier release does not authorize subsequent synchronization or publishing. A GitHub synchronization request alone does not authorize a Homebrew release.
- Completing development, fixes, reviews, version changes, tests, builds, or local packaging must not automatically trigger a push, tag publication, GitHub release, public artifact upload, or Homebrew publication.
- Prepare and verify the requested work locally. Without the corresponding explicit user command, leave remote repositories and published releases unchanged.

## UI Design

- Follow [design.md](design.md) for UI-only changes and visual verification. Preserve existing features, preferences and data behavior.

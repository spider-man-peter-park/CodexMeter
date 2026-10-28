# CodexMeter

A small, native macOS menu bar companion for **OpenAI Codex Desktop**. Swift + SwiftUI + AppKit; no Electron, service, database, API key, or third-party runtime dependencies.

```text
Compact: 5h 82% | 7d 61% | 73 TPS
Full:    5h 82% 2h14m | 7d 61% 4d8h | 73 TPS
```

These are examples, not hardcoded readings. Click the menu bar text for quota bars, reset countdowns, response details, refresh, settings and Quit. Missing data is `—`; a window absent from an otherwise valid account response is `N/A`. `*` marks cached or stale quota. An account with only weekly quota stays weekly-only.

## Install and run

Requires macOS 14 or later and an already signed-in Codex Desktop installation. The locally built release is for Apple Silicon; build from source on an Intel Mac. Codex may be installed as Codex.app or integrated in ChatGPT.app. CodexMeter checks registered applications and standard install paths before falling back to `codex` in PATH.

Download [CodexMeter-macOS-arm64.zip](https://github.com/spider-man-peter-park/CodexMeter/raw/refs/heads/main/dist/CodexMeter-macOS-arm64.zip) and unzip it, move `CodexMeter.app` into `/Applications`, then open it. It has no Dock icon or main window. This MVP is ad-hoc signed, not Apple notarized; building locally is the most direct option if macOS blocks a downloaded copy. For a downloaded build, use the standard macOS Privacy & Security “Open Anyway” flow only if you trust this repository. The app requests no Accessibility, Screen Recording or network interception permissions.

Launch at login is off until enabled in Settings. Install in Applications before enabling it. macOS may require approval in System Settings → General → Login Items. All other settings are in the popover: compact/full, each quota window, countdown in full mode, TPS and automatic refresh. Automatic refresh controls background quota and log checks; manual refresh always works. The local countdown still ticks once a minute.

## Build and test

With Xcode 16+ or the Swift 6 Command Line Tools installed:

```bash
./scripts/test.sh
./scripts/build-app.sh
open build/CodexMeter.app
```

`build/CodexMeter.app` is self-contained. The build script signs it ad hoc. It inherits the architecture of the build machine. No package downloads are needed.

Alternatively open `CodexMeter.xcodeproj`, choose the CodexMeter scheme and build/run. The native app target links the local `CodexMeterCore` Swift package. `Package.swift` can also be opened in Xcode for the Swift Testing unit tests. Regenerate the app project after adding app source files with `python3 scripts/generate-xcode-project.py`.

```bash
xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter \
  -configuration Release -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Inside a restricted build environment, SwiftPM may need an explicit writable scratch directory and `--disable-sandbox` for its nested build sandbox:

```bash
./scripts/test.sh --disable-sandbox --build-system native --scratch-path /private/tmp/codexmeter-tests
./scripts/build-app.sh --disable-sandbox --build-system native --scratch-path /private/tmp/codexmeter-build
```

If a synced Documents folder adds Finder metadata that prevents code signing, set `CODEXMETER_OUTPUT_DIR=/private/tmp/CodexMeter-build` when invoking the build script, or build in a local non-synced folder.

The test script discovers the installed Swift Testing macro plugin. The current development machine has Command Line Tools without full Xcode; the native `.app` and unit tests are built locally. The included GitHub Actions workflow separately exercises the Xcode app project on a full Xcode runner. Both that Xcode build and the standalone app build passed during initial delivery.

## Data and refresh behavior

Quota reads launch the installed Codex executable's `app-server --help` first, select its supported stdio transport, then exchange newline-delimited JSON-RPC:

1. `initialize` / `initialized`
2. `account/read` with `refreshToken: false`
3. `account/rateLimits/read`

There is no login, reset-credit, turn, thread, tool or coding request. The child process uses the existing signed-in Codex account. CodexMeter never reads or stores authentication files/tokens. Analytics and OpenTelemetry exporters are disabled for this child with in-memory command arguments; Codex configuration and app files are not edited. The app itself has no HTTP client; the Codex subprocess performs its normal account/quota service traffic.

The read-only query has a 15-second total timeout, bounded output and cancellation handling. Each query closes pipes, terminates the child and reaps it, escalating to SIGKILL only if it will not exit. It runs once at launch and every 180 seconds while automatic refresh is on, or on manual refresh. Queries never overlap. Countdown text updates locally every 60 seconds. Transient failures preserve the last valid quota, its timestamp and a stale marker. Recent local `rate_limits` snapshots are a fallback, always labeled cached and potentially outdated. Expired reset times do not manufacture replenished quota; the countdown says `now` until a fresh reading arrives.

Percentages are clamped to `max(0, min(100, 100 - usedPercent))`. Windows are selected by duration, 300 and 10080 minutes, regardless of primary/secondary order. The `codex` bucket is used when the multi-bucket API is available; unrelated model buckets are never merged.

## Effective TPS and accuracy

TPS is **one completed model response's output tokens divided by its effective elapsed seconds**, including prefill/first-token waiting where boundaries allow. It is not streaming decode speed, task-wide throughput or a performance benchmark. Every log-derived sample is labeled estimated. Reasoning output is already included in output tokens and is never added again.

The parser examines structural event fields, not text contents:

- `task_started`, `turn_context` and completed input items establish a sampling boundary.
- Reasoning, assistant messages and tool-call response items establish the final generated-item timestamp.
- Modern `token_usage_record` provides a stable response ID and per-response usage, often before local tools finish. On older recognized logs, `token_count.info.last_token_usage` supplies the increment. Cumulative usage is only a deduplication fingerprint, never a single response's output.
- Completed tool outputs advance the next response boundary; parallel local tools must all finish. Tool-call generation belongs to the preceding model response; local tool execution is excluded from the next response's time window. Boundaries do not use arbitrary gaps between token-count timestamps.
- Cancelled/incomplete responses, damaged JSON, missing input/output boundaries, invalid usage, zero/nonpositive timing and unsupported old event sequences cannot produce TPS. A newer unmeasurable request keeps the last valid sample and displays its actual completion time.
- Repeated response IDs, item IDs and cumulative usage are deduplicated. First-file metadata is authoritative. Known CLI sessions, subagents and automatic guardian reviews are excluded. Forked history must match the current session's thread ID; ambiguous legacy fork usage is rejected.

Recognized `originator: "Codex Desktop"` main sessions are preferred globally by completion time, across concurrent sessions and archives. If source metadata is missing, otherwise supported logs can be used only when no Desktop sample is available; CLI records sharing the same CODEX_HOME may therefore be counted when they cannot be reliably identified.

Local timestamps describe persisted events rather than server-side token generation. OS scheduling, event buffering, remote built-in tool work, input queue delays and network waiting can affect the estimate. The app cannot subtract an internal tool interval absent from logs. It deliberately shows no number when no defensible timing window exists. It does not infer hidden reasoning timings from visible text length.

## Incremental files and privacy

The default roots are `~/.codex/sessions` and `~/.codex/archived_sessions`. File changes are checked about every two seconds. Directory listings are cached by modification time, cursors are keyed by device/inode so archival renames preserve progress, and only appended bytes are parsed. Startup backfill is newest-file-first and bounded per pass; large histories may take several passes. Partial final JSONL records wait for their newline. Individual unsupported records over 8 MiB invalidate their timing window instead of allocating unbounded memory. Checkpoints preserve only cursors, boundary timestamps, model names, opaque deduplication IDs and token/quota counters. Prompt/response text and incomplete line bodies are never saved or logged. File truncation/replacement resets its parser.

Checkpoints are stored with private file permissions in `~/Library/Application Support/CodexMeter/`. Last valid quota and display preferences use UserDefaults. Nothing is uploaded by the app: no conversations, usage counters or project paths. There is no telemetry, updater, proxy, sync, cloud service or account switcher.

For custom CODEX_HOME, launch from a shell with the environment variable, or configure the persistent path for Finder launches:

```bash
defaults write io.github.codexmeter.app codexHome -string "/absolute/path/to/codex-home"
```

Quit and reopen after changing it. Restore the default with `defaults delete io.github.codexmeter.app codexHome`.

## Diagnostics

The executable can print a small local numeric status report, without prompts, replies, session paths or credentials:

```bash
build/CodexMeter.app/Contents/MacOS/CodexMeter --diagnose
```

It makes one normal quota query. `--show-popover` opens the panel at launch for UI inspection. Do not post diagnostics or screenshots publicly if you wish to keep your usage metrics private.

## Uninstall

Turn off Launch at login in the app, quit CodexMeter and move the app to Trash. Optionally delete its settings and derived checkpoints:

```bash
defaults delete io.github.codexmeter.app
rm -rf "$HOME/Library/Application Support/CodexMeter"
```

This never removes Codex sessions or authentication/configuration files.

## References and license

Independent Swift implementation under the [MIT license](LICENSE). The response-boundary approach was researched against [adenta/codex-tps](https://github.com/adenta/codex-tps), MIT, Copyright 2026 Andrew. No source code from that project was copied. CodexMeter additionally handles modern response usage IDs, Desktop provenance, fork replay, cancellation and persistent incremental state.

Protocol reference: [official Codex App Server documentation](https://learn.chatgpt.com/docs/app-server). Local help and actual event structures remain the source of compatibility checks. This is an independent companion, not an OpenAI product.

# CodexMeter

A small, native macOS menu bar companion for **OpenAI Codex Desktop**. Swift + SwiftUI + AppKit; no Electron, service, database, API key, or third-party runtime dependencies.

The menu bar contains **four independent native items**, one for each quota window, one for TPS and one for today's local tokens. Default examples:

| Item | Text |
| --- | --- |
| 5-hour quota | GPT icon + `82% · 2h14m` |
| 7-day quota | GPT icon + `61% · 4d8h` |
| Latest response | Lightning symbol + `TPS` stacked above `73` |
| Today's local tokens | Stacked squares symbol + `69.2M` |

These are examples, not hardcoded readings. Each item can be hidden separately and moved independently using the standard macOS Command-drag gesture. Click any item for the common detail panel, including quota bars, response details, account token statistics, remaining reset-credit cards, refresh, settings and Quit. Hovering identifies which quota window an `AI` item represents.

When a successful quota response reports only a 7-day window, CodexMeter hides both 5-hour switches in Settings and turns off 5-hour menu bar display and notification monitoring. This removes the extra `N/A` item. The last confirmed window availability is retained across restarts. Failed reads, log fallbacks and responses containing only reset credits do not change that availability. If a later live response reports a 5-hour window, its switches return in the off state and can be enabled manually. Before any window availability is known, the original defaults remain available.

Quota labels can be **AI**, **5h / 7d**, **Window icons**, **GPT icon**, **Custom**, or **None**. The GPT option uses the original black/white OpenAI Blossom assets from the [official logo package](https://cdn.openai.com/brand/OpenAI-Logos-2025.zip), bundled locally, and keeps the two quota items independent. Reset countdowns appear immediately after the remaining percentage and have their own toggle, with compact (`2h14m`, `4d8h`) or clock (`02:14`, `4d08:00`) formatting. TPS has 0/1 decimal-place and suffix controls. Appearance settings include Minimal/Balanced/Elegant presets, 9–16 pt system/rounded/monospaced fonts, weight, monochrome or accent colors, capsule backgrounds, spacing, SF Symbols or custom labels, the percent sign, and countdown separators. Presets preserve which metrics are visible and the refresh periods. If all metrics are hidden, a small `AI` item keeps settings accessible.

New installations use GPT icons, 12 pt medium system text, compact spacing, dot-separated compact countdowns, and stacked TPS with no decimal places. All four menu bar metrics and their labels remain visible, subject to the account's confirmed quota windows. The system supplies the selected background while a menu item's detail panel or context menu is open; the app supplies template glyphs so macOS controls their contrast. Background settings can also keep custom capsules visible while inactive or use plain labels. Existing saved preferences take priority over these defaults.

Settings → Labels & visible metrics → Show today's tokens controls the independent stacked-squares-and-count item and persists across restarts. It defaults to on when upgrading from settings that predate this option. The value uses the same local total as Today · this Mac, with compact K/M/B/T units; it includes input plus output without adding cached/reasoning subtotals again. Missing, incomplete empty or previous-day readings show `—`; a complete day with no usage shows `0`. Partial readings retain their estimate/backfill qualifiers in hover help. Changing this switch does not affect quota, TPS, reminders or log collection.

TPS includes a lightning symbol to the left of its value in both Inline and Stacked layouts. Settings → Labels & visible metrics → Show TPS lightning icon controls this symbol independently of Show TPS label and Show TPS. The new switch defaults to on; explicit off values persist across restarts and appearance presets preserve the choice. Today · this Mac uses the same stacked squares symbol in its detail heading and layout settings.

Selected images never contain a custom background, preventing a second capsule inside the system's selected pill. An Always capsule returns after dismissal. Item geometry stays stable across selection, and no native button highlight overrides are installed. This applies to both quota and TPS items without changing saved appearance choices.

The panel closes when you click another application or switch away, including after editing settings. Pending anchor changes are cancelled on dismissal so changing metric visibility cannot reopen it after an outside click.

Clicking any menu bar item also refreshes quota, account statistics and local TPS, even with automatic refresh turned off. In-flight reads are reused rather than overlapped. Accounts without a reported 5-hour window omit that row in the details. The TPS layout can be Inline or Stacked, with a small TPS label above a larger number; its precision and label visibility remain independent settings.

Missing data is `—`; a window absent from an otherwise valid account response is `N/A`. `*` marks cached or stale quota. An account with only weekly quota stays weekly-only. Version 0.2 migrates the original compact/full preference to independent controls and initially selects AI labels with countdowns enabled.

## Install and run

Version 0.4.1 bundles the conditional five-hour controls, portable app resource lookup for Alfred launches, single native selected background, compact Today totals, stacked-square token item and optional TPS lightning icon. Existing preferences are retained; the two new menu bar options default to on until explicitly disabled.

Requires macOS 14 or later and an already signed-in Codex Desktop installation. The locally built release is for Apple Silicon; build from source on an Intel Mac. Codex may be installed as Codex.app or integrated in ChatGPT.app. CodexMeter checks registered applications and standard install paths before falling back to `codex` in PATH.

Download [CodexMeter-macOS-arm64.zip](https://github.com/spider-man-peter-park/CodexMeter/raw/refs/heads/main/dist/CodexMeter-macOS-arm64.zip) and unzip it, move `CodexMeter.app` into `/Applications`, then open it. It has no Dock icon or main window. This MVP is ad-hoc signed, not Apple notarized; building locally is the most direct option if macOS blocks a downloaded copy. For a downloaded build, use the standard macOS Privacy & Security “Open Anyway” flow only if you trust this repository. The app requests no Accessibility, Screen Recording or network interception permissions.

### Homebrew

Install the Apple Silicon build from this repository's custom tap:

```bash
brew tap spider-man-peter-park/codexmeter https://github.com/spider-man-peter-park/CodexMeter
brew install --cask spider-man-peter-park/codexmeter/codexmeter
open -a CodexMeter
```

The cask requires macOS 14 or later, installs `CodexMeter.app` into `/Applications`, and checks a SHA-256 against an immutable version-specific download. It uses the standard Homebrew quarantine behavior; the same signing and first-launch considerations above apply. This is a third-party tap, separate from the official Homebrew Cask repository.

```bash
brew update
brew upgrade --cask spider-man-peter-park/codexmeter/codexmeter
brew uninstall --cask spider-man-peter-park/codexmeter/codexmeter
```

Before uninstalling, turn off Launch at Login in Settings. If the interface is unavailable, run `/Applications/CodexMeter.app/Contents/MacOS/CodexMeter --unregister-login-item` first. Homebrew quits the app during removal. Login-item registration is preserved during upgrades.

For a complete removal of CodexMeter's own preferences and derived checkpoints, use `brew uninstall --cask --zap spider-man-peter-park/codexmeter/codexmeter`. Codex session and authentication files are never part of the cask's uninstall or zap paths.

When publishing an update, upload and verify the app archive first, then update `Casks/codexmeter.rb` with its version, immutable commit URL and SHA-256, together with the public `updates.json` version. Update the tap with `brew update` to make that version available through `brew upgrade`.

New installations request Launch at Login once on first launch. Install in Applications before opening the app; macOS may require approval in System Settings → General → Login Items. Existing installations keep their current system login-item state, and later launches do not re-enable a disabled item. Change this option in Settings at any time. All other settings are grouped in the popover: appearance presets and typography, labels and visible metrics, refresh periods, and general settings. Automatic refresh controls background quota and log checks; manual refresh always works. The local countdown keeps ticking at the selected display period.

Settings are also available in a native, reusable window through **Settings…** or **Command-,** while CodexMeter is active. Right-click a menu bar item for Settings, About, update checks, GitHub, feedback and Quit. Closing Settings leaves the menu bar app running. About uses the bundle's version, build number, icon and copyright. The detail header omits the version badge.

### Interface design

The 0.4 interface uses flat detail sections, a compact subscription nameplate, consistent monospaced metrics and semantic light/dark surfaces. Settings has a resizable native window with six sidebar categories; the existing inline settings remain available. Every existing preference and data behavior is retained. The font-size minus/plus buttons adjust the existing 9–16 pt preference in one-point steps.

See [design.md](design.md) for typography, spacing, components, official references and the actual screenshot review record. UI preview launch arguments affect only the current process and never overwrite the user's saved language, section layout or system appearance. Version 0.4.0 includes this interface update and the documented default configuration.

The Subscription row displays the plan identifier reported by Codex with a readable label, such as Plus or Pro Lite. Explicit identifiers such as `pro5x` and `pro10x` display their multiplier. A generic `pro` or `prolite` response does not include an account-specific allowance multiplier, so the app does not guess one or turn a temporary usage promotion into a subscription label.

### Detail panel layout

The detail header uses “Know your limits. Keep your focus.” and omits the version badge; the version remains available in About. Opening details from a menu bar item does not activate a covered Settings window. The current subscription appears as a distinct nameplate. Reset credits sit at the bottom of Plan limits as a collapsed count/expiry summary; expand the row for the returned card details. Today · this Mac shows the local total tokens and usage-record count followed by the account’s latest seven reported dates; Input and Output breakdowns are omitted, and account totals are never added to the local estimate. The local date/timezone, estimate badges, token-detail disclosure, update time and account-report status rows are omitted from this compact card. Scope and partial-estimate information remains in hover help. Account usage keeps lifetime/streak statistics and the expandable daily token history. Longer explanations and local estimate qualifiers are available through hover help; cached and unavailable states retain brief status labels.

Settings → Detail panel layout lists all five sections: Plan limits, Today · this Mac, Latest response, Account usage and Settings. The default shows the first three sections and hides Account usage and inline Settings. Use the up/down arrows to arrange them and the switches to show or hide each section. Hidden sections retain their positions. Layout choices persist across restarts and language changes independently of menu bar items and data-refresh preferences. Default layout restores only this section layout. The fixed footer’s Settings button and Command-, remain available even if every section is hidden. Hiding a section changes presentation only; monitoring and reminders continue according to their own settings.

### Language

CodexMeter supports English and Simplified Chinese. Settings → General → Language offers Follow System, 简体中文 and English. The default follows the preferred app/system language, with English as the fallback for other languages. Switching takes effect immediately for details, settings, menus, charts and status hints. New notification content uses the selected language; notifications already scheduled by macOS retain their original text. Subscription/model identifiers, custom labels, TPS, compact Token units and menu bar countdown units remain unchanged.

### Update checks

Automatically Check for Updates is off by default. When enabled, CodexMeter checks the project's public `updates.json` about every 12 hours, with a manual Check for Updates action available at any time. It only announces newer versions and opens the project page; installation remains manual or through Homebrew. Checks have a timeout, avoid overlapping requests and back off after failures. Disabling the switch cancels an ongoing check and removes the update-check timer.

### Quota and reset-credit notifications

The default configuration enables Low quota alerts, Quota recovery alerts and Reset credit expiry reminders, monitors both quota windows at 10%, and selects three days before credit expiry. Existing saved notification preferences, including disabled alerts, are preserved. On a new installation, click Enable Notifications in Settings → Notifications to grant macOS permission; startup never requests permission automatically. If permission is denied, allow CodexMeter in System Settings → Notifications; returning to the app refreshes its permission status.

Quota alerts can monitor the 5-hour and 7-day windows independently. Choose 20% and 10%, 10%, or 5% thresholds. Crossing several thresholds between reads produces one alert at the most urgent level. Delivery acknowledgements persist across restarts. Recovery requires an observed low reading followed by a successful live reading at least five percentage points above the highest selected threshold (15% with the default threshold). Minor fluctuations do not repeatedly rearm alerts. A passed reset countdown, cached logs, saved snapshots or a missing window cannot manufacture a recovery notification.

Reset-credit reminders support three days, one day, or both before expiry. Only cards explicitly reported as available with a known future expiry are eligible; unknown status, missing detail rows and count-only responses never produce guessed reminders. Fresh authoritative reads cancel scheduled notifications for used, missing or expired cards. Disabling expiry reminders cancels their pending notifications. Already scheduled notifications can be delivered by macOS while the app is closed or offline, so their wording explicitly refers to the last reported availability; a card consumed elsewhere cannot be discovered until a new successful read.

Enable Automatic Refresh for background quota monitoring. Notification clicks open the detail panel. Notification content excludes card IDs, account identifiers, session paths and conversation content. Notifications are local; no push server or account credentials are required.

### Wake and network recovery

With Automatic Refresh enabled, macOS wake and a network-path transition from unavailable to available request a single calibration of quota, account statistics and local responses. The initial network-path callback does not duplicate the launch refresh. Events within three seconds are merged, in-flight reads are reused, and recent attempts retain minimum intervals of 60 seconds for quota and 300 seconds for account statistics. Repeated failures extend the recovery cooldown exponentially, capped at 15 and 30 minutes respectively. This adds no network reachability polling or repeated automatic retry loop, and a satisfied network path is not a guarantee that the Codex service is reachable.

Pending calibration is cancelled on sleep, app termination or disabling Automatic Refresh. A wake still updates the local countdown when automatic reads are disabled. Manual refresh remains available. The existing quota calculation, App Server protocol, cache format and TPS parsing are unchanged.

## Build and test

With Xcode 16+ or the Swift 6 Command Line Tools installed:

```bash
./scripts/test.sh
./scripts/build-app.sh
open build/CodexMeter.app
```

`build/CodexMeter.app` is self-contained. The build script signs it ad hoc. It inherits the architecture of the build machine. No package downloads are needed.

The build script also runs `CodexMeter --verify-resources` against the packaged application. This checks that localization is loaded from the app's own resource bundle and that both languages and the bundled artwork are available, without opening windows or reading account data. Installed applications must continue to launch after the SwiftPM scratch directory is removed.

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

There is no login, reset-credit, turn, thread, tool or coding request. The child process uses the existing signed-in Codex account. CodexMeter never reads or stores authentication files/tokens. Analytics and OpenTelemetry exporters are disabled for this child with in-memory command arguments; Codex configuration and app files are not edited. The Codex subprocess performs its normal account/quota service traffic. The app's separate update-check client contacts GitHub only when automatic checks are enabled or the user requests a manual check.

The read-only query has a 15-second total timeout, bounded output and cancellation handling. Each query closes pipes, terminates the child and reaps it, escalating to SIGKILL only if it will not exit. Quota reads run once at launch and every 180 seconds by default, or on manual refresh. The quota period can be set to 1, 3, 5, 10 or 15 minutes. Account statistics default to 15 minutes, with 5, 15, 30 and 60 minute choices. Each query type prevents overlapping requests. Local response checks support 1, 2, 5, 10 or 30 seconds; countdown text supports 15, 30 or 60 seconds. Period changes reschedule the timers immediately. Manually edited preferences retain minimum network periods of 60 seconds for quota and 300 seconds for account statistics. Transient failures preserve the last valid quota, its timestamp and a stale marker. Recent local `rate_limits` snapshots are a fallback, always labeled cached and potentially outdated. Expired reset times do not manufacture replenished quota; the countdown says `now` until a fresh reading arrives.

Percentages are clamped to `max(0, min(100, 100 - usedPercent))`. Windows are selected by duration, 300 and 10080 minutes, regardless of primary/secondary order. The `codex` bucket is used when the multi-bucket API is available; unrelated model buckets are never merged.

## Account token statistics

`account/usage/read` supplies the same account-wide statistics exposed by the supported Codex account surface: lifetime tokens, peak daily tokens, current and longest streak, longest running turn, and per-date token totals. These are server account statistics, distinct from the latest response's TPS and local log history. The account query uses only `account/read` and `account/usage/read`, never inference or conversation APIs.

Token counts in the detail panel use decimal K/M/B/T units with at most one decimal place and no trailing `.0`, for example `1.3B` or `22M`. Counts below 1,000 remain whole numbers; unavailable values remain `—`. This display formatting does not change the stored counts or TPS calculations.

Daily buckets retain the exact `YYYY-MM-DD` labels reported by Codex. Reporting may lag; the latest returned day is explicitly labeled and a missing current day is never shown as zero or silently substituted with the preceding day. All returned dates can be expanded. Null summary fields stay unavailable. Separate timestamps and stale indicators identify cached account statistics after failures or restart. Only the whitelisted counters, dates and plan label are retained; account email, account IDs, avatars and thread-level usage are not persisted.

The detail panel includes an interactive line chart of the seven calendar days ending on the latest reported date, with its exact range shown. Select a day to inspect its token count. Missing dates remain gaps and are not joined across or counted as zero; explicitly reported zeroes are plotted at zero. The chart uses the same compact K/M/B/T labels and read-only account statistics as the daily list, with no additional queries or stored history.

### Today on this Mac

The separate **Today · this Mac** card estimates input plus output tokens recorded since midnight in the Mac's current time zone. Cached input is already part of input, and reasoning output is already part of output; their optional detail counters are never added twice. Counts follow each usage record's timestamp, so a response spanning midnight is assigned when its usage is reported. Daily totals are independent of whether a response has enough timing evidence to calculate TPS.

Only explicitly identified Desktop sessions and subagents traceable to those sessions are counted. Known CLI and automatic review sessions are excluded; unidentifiable or unsupported records are not guessed. This covers locally available logs, not a guaranteed account-wide total across devices or cloud tasks. The account's daily buckets keep their original server dates and are never added to the local estimate.

Startup backfills today's modified logs, including long-running sessions created on earlier days. A bounded migration upgrades the existing checkpoint without losing the last valid TPS sample; ordinary reads remain incremental. Response IDs and cumulative-counter aliases deduplicate modern/legacy copies, archival moves, restarts and replay. Forked parent usage cannot become a child's new usage. Mixed schemas without enough identity evidence are reported as partial instead of counted twice.

The app keeps only three days of whitelisted usage counters, UTC timestamps and hashed identities so current-day totals can be recomputed after restart or time-zone changes. Checkpoints are private and contain no conversation bodies, project paths or authentication information. A 100,000-record safety limit and unreadable/unsupported data produce a partial-estimate warning. Backfill progress is explicit; unavailable counts are not shown as zero. After midnight with Automatic Refresh off, manually refresh to populate the new day.

### Recent TPS chart

The Latest response card also plots the **last 30 valid completed responses**, ordered oldest to newest by completion time. The horizontal axis is response order, not equal elapsed-time intervals. Select a point for its model, TPS and completion time. Lines break when the model changes; the existing effective-TPS calculation is unchanged. Invalid or unmeasurable responses are omitted, never plotted as zero, and fewer than 30 available samples remain a shorter series.

History is bounded, persisted, backfilled and deduplicated across sessions and restarts. The existing Desktop-first source policy applies; if only unattributed samples are available, a warning explains that CLI responses may be included. The chart is a recent local observation, not a comparison benchmark between models.


## Remaining reset credits

The detail panel reads `rateLimitResetCredits` from the existing read-only quota response. It shows the server's authoritative available count plus each returned card's title, status, grant time, expiration time and description. Times use the Mac's local time zone. The app does not consume cards or invoke any reset API.

Unknown credit data stays unavailable, never zero. A count-only response is labeled explicitly; an empty or capped detail list does not change the server's count. Cached or restored credit data shares the snapshot's timestamp and stale indication. Older saved quota snapshots remain readable when they have no credit fields.

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

The default roots are `~/.codex/sessions` and `~/.codex/archived_sessions`. File changes are checked every two seconds by default, with the period configurable in Settings. Directory listings are cached by modification time, cursors are keyed by device/inode so archival renames preserve progress, and only appended bytes are parsed. Startup backfill is newest-file-first and bounded per pass; large histories may take several passes. Partial final JSONL records wait for their newline. Individual unsupported records over 8 MiB invalidate their timing window instead of allocating unbounded memory. Checkpoints preserve only cursors, boundary timestamps, model names, opaque deduplication IDs and token/quota counters. Prompt/response text and incomplete line bodies are never saved or logged. File truncation/replacement resets its parser.

Checkpoints are stored with private file permissions in `~/Library/Application Support/CodexMeter/`. Last valid quota, account statistics and display/refresh preferences use UserDefaults. Nothing is uploaded by the app: no conversations, usage counters or project paths. Optional update checks download only public version metadata from GitHub, without authentication, cookies or account information; the preference, last check time and last published version are saved locally. There is no telemetry, automatic installer, proxy, sync, cloud service or account switcher.

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

It makes one normal quota query. `--show-popover` opens the panel at launch; `--inspect-ui` is an alias with the same normal outside-click dismissal. Do not post diagnostics or screenshots publicly if you wish to keep your usage metrics private.

## Uninstall

Turn off Launch at login in the app, quit CodexMeter and move the app to Trash. Optionally delete its settings and derived checkpoints:

```bash
defaults delete io.github.codexmeter.app
rm -rf "$HOME/Library/Application Support/CodexMeter"
```

This never removes Codex sessions or authentication/configuration files.

## References and license

Independent Swift implementation under the [MIT license](LICENSE). The optional OpenAI logo assets are trademarks of OpenAI and are excluded from that license; see [asset sources](Sources/CodexMeterApp/Resources/ASSET-SOURCES.md) and [OpenAI brand guidelines](https://openai.com/brand/). The response-boundary approach was researched against [adenta/codex-tps](https://github.com/adenta/codex-tps), MIT, Copyright 2026 Andrew. No source code from that project was copied. CodexMeter additionally handles modern response usage IDs, Desktop provenance, fork replay, cancellation and persistent incremental state.

Protocol reference: [official Codex App Server documentation](https://learn.chatgpt.com/docs/app-server). Local help and actual event structures remain the source of compatibility checks. This is an independent companion, not an OpenAI product.

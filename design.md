# CodexMeter UI design specification

## Direction and scope

Native macOS + Refined Minimalism. This is a compact monitoring utility, not a web dashboard. Keep the existing menu bar items, five configurable detail sections, every preference, all data semantics, account queries, notifications and storage formats. Retain the user-approved slogan and compact Today/TPS contents; no version badge in the detail header. All new source comments remain English.

## Evidence and design tools

- `ui-ux-pro-max` is installed and was used with a whole-product design-system query, a narrower desktop retry, SwiftUI settings/form guidance and chart guidance. The matched Minimalism style, native form controls, consistent spacing, semantic colors, labels and reduced-motion checks apply. The generated Hero/CTA pattern, web fonts, GSAP, mobile target dimensions and JavaScript chart libraries do not fit this app and are explicitly rejected. The numeric-alignment UX search and its retry did not return a verified native match; the typography below is an explicit macOS system-font decision, not an attributed database result.
- Actual pre-redesign app screenshots are in the task's `work/ui-redesign/baseline/` folder. Findings: oversized subscription decoration, repeated rounded borders, small captions, a long unstructured settings form, inconsistent control alignment and weak hierarchy.
- Umbra: official [product](https://replay.software/umbra), inspected actual [light settings](https://replay.software/umbra/images/WindowSettingsLight.jpg) and [dark settings](https://replay.software/umbra/images/WindowSettingsDark.jpg). Adopt its single grouping level, consistent label/control columns and neutral surfaces. Do not copy its layout/assets.
- Revisual: official [product](https://revisualapp.com/) and inspected [settings screenshot](https://revisualapp.com/Revisual-settings.webp). Adopt persistent category navigation, pane title hierarchy, aligned trailing controls and restrained separators. Do not copy its glow or product-specific content.
- Apple: [macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos), [Settings](https://developer.apple.com/design/human-interface-guidelines/settings), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Color](https://developer.apple.com/design/human-interface-guidelines/color), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility). Prefer native control behavior over web-style custom interactions.

## Typography

Use SF system fonts only. App/pane titles 15/20 pt semibold; section headings 12 pt semibold; body and controls 13 pt regular; auxiliary labels and chart axes 11 pt; primary metrics 28 pt medium with monospaced digits; secondary metrics 15 pt semibold with monospaced digits. Units use 11–12 pt secondary text aligned to the numeric baseline. Keep long model names middle-truncated and plan names able to wrap. No third-party fonts or automatic all-caps Chinese labels.

## Spacing and layout

Base scale: 4, 8, 12, 16, 20, 24 pt. Popover width remains 420 pt, with existing screen-height bounds. Header 16–20 pt inset, content gutters 20 pt, sections 16 pt vertical padding, inner row gaps 8–12 pt. Use a single divider between sections rather than a border around every section. Keep the footer outside the scroll view with clear separation; focused content must remain scrollable. Reserve loading and chart-detail slots to reduce jumps. Settings use a native sidebar of about 168 pt and a readable content pane with 24 pt insets. Keep an inline disclosure presentation for the existing detail Settings section.

## Color and surfaces

Use `windowBackgroundColor`, `controlBackgroundColor`, `labelColor`, `secondaryLabelColor`, `separatorColor`, and the system accent. One accent is sufficient for selected controls and charts. Orange/red retain their existing warning meanings and are accompanied by text/icons. No gradients, glow or added shadows in content. One restrained subscription nameplate/pill provides identity without becoming a second card. Keep system focus rings and native disabled states. Light/dark variants derive from semantic colors, not black/white opacity assumptions.

## Corners and icons

Use 6 pt for a compact badge and 8 pt only when grouping actually needs a surface. Let native buttons/fields use native corner geometry. Use SF Symbols at 12–14 pt, regular/medium visual weight within a hierarchy. Keep original official GPT artwork and existing menu bar label choices. Decorative symbols beside text are accessibility-hidden; icon-only actions keep names and hover help.

## Components

A shared UI-only style file owns typography, spacing and semantic surfaces. Detail sections are flat; metric columns align consistently; empty and stale states use concise secondary labels. Settings have persistent categories and clear page titles, a single grouping level, native pickers/toggles/steppers, and stable trailing control alignment. All existing choices and bindings must survive the refactor, including layout arrows, visibility switches, labels, fonts, refresh, login, notifications and updates. The footer's Settings action and Command-comma remain reachable when all detail sections are hidden.

## Motion and adaptation

Use native pressed/hover/focus feedback. No animated number interpolation, continuous shimmer or chart morphing. Optional short 0.16–0.20 s presentation transitions must honor Reduce Motion; use immediate state updates when reduced motion is enabled. Keep menu bar native appearance updates and existing popover dismissal/reanchor logic unchanged. Support system light/dark, English/Chinese, resizable Settings and existing minimum screen-height handling. UI-only launch preview flags may select an app-local appearance for QA; never persist them or change global macOS appearance.

## Verification contract

Before implementation, capture the baseline. Perform two implementation/screenshot/review/correction rounds, covering details and Settings, and both appearances where tools permit. Save actual screenshots, identify what each round found and what was corrected, and distinguish screenshot evidence from code/unit evidence. Do not claim VoiceOver, system-wide contrast settings, native menu bar screenshots or window stacking tests that were not performed. Unit and build checks do not substitute for actual visual inspection.

## Review log

Baseline: actual light popover and Settings screenshots captured. No baseline dark-mode claim. Implementation rounds and limitations will be appended after the observations occur.

Round 1 (actual light + app-local dark captures): flat sections and the reduced nameplate allowed the complete seven-day axis to fit in the first light viewport. General, Appearance and Layout panes were inspected. Found an AX-present but visually absent font stepper, centered intrinsic menu pickers, excess accent on sidebar symbols, and a dark-preview popover inheriting a light anchor appearance. Corrections: explicit intrinsic stepper bounds, trailing menu-column alignment, semantic sidebar symbols, app-appearance synchronization for the popover, and removal of newly-added minimize behavior. The first dark popover screenshot is retained as failure evidence, not a dark-mode pass. A wider inline control column will be checked in English during Round 2.

Round 2 dark review: the popover now actually uses dark surfaces and readable foregrounds, and the right-aligned menu columns and neutral sidebar symbols are visible in actual screenshots. The explicit SwiftUI Stepper frame still did not produce visible mouse controls. Corrective follow-up replaces only that UI adapter with AppKit's native NSStepper, retaining the same Double binding, 9–16 range and increment of one. No setting or storage format changes. Follow-up screenshots will confirm the correction; English/all-section previews use volatile argument-domain overrides only.

Round 2 corrections also keep warning text in the semantic primary foreground with an orange symbol, rather than coloring an entire small-text sentence orange. Section headings use primary text so they are not visually subordinate to chart subheadings. Neither correction changes the underlying warning conditions or information.

Follow-up English/light review: both English segmented labels and sidebar wrapping were readable, but NSStepper still had no visible arrows in the actual screenshot. Final correction therefore uses two repeatable native bordered minus/plus buttons, retaining the existing font-size binding, normalization, 9–16 bounds and one-point increments. This is a UI adapter only; the invisible stepper implementations are removed. The final capture must verify discoverable buttons before acceptance.

Final follow-up: Build 18 actual light/English and dark/Chinese Appearance screenshots show both minus/plus buttons clearly. Dark Labels, Refresh and Notifications panes were also captured; visible text and controls fit without observed truncation. Notifications retains its longer existing permission/accuracy explanations. Build 19 uses the bundled application icon explicitly; its actual light/English popover screenshot shows the compact icon, full slogan, complete seven-day chart axis, primary section headings and separated footer. The icon file itself is unchanged.

Verification: the final production build succeeded and all 148 tests passed (129 Core, 19 app). Four added rendering tests cover both appearances, all quota labels, font-size bounds, capsule activity, color styles and inline/stacked TPS. Eight optional renderer exports are raw render previews, not screenshots of the macOS menu bar. All non-resource Core files and the app model, reminders, updates, metadata and recovery monitor match the pre-redesign hashes. The seven whitelisted saved preference values/hashes also match the baseline; preview overrides were volatile. Xcode is unavailable on this machine; the Swift/Command Line Tools build has nonfatal missing search-path warnings. No full-Xcode or CI result is claimed for this revision.

Limits: actual detail and Settings screenshots cover two implementation/review/correction rounds and both app-local appearances. No global macOS appearance was changed. Attempts to scroll the final transient popover for lower TPS/Account and inline Settings captures failed with stale-element, timeout and changed-state errors; those lower layouts have source/binding verification but no successful final screenshot. The full native system menu bar, covered-window stacking, smallest-screen resizing, VoiceOver end-to-end, Increase Contrast and Reduce Motion settings were not manually validated. No custom continuous animation was introduced. These are open verification limits, not completed accessibility certification. Screenshot timestamps and metric values differ because they show live readings.

Delivery remains local. The application, working-tree source and screenshot evidence are packaged separately; GitHub, update feeds and Homebrew remain unchanged until an explicit new user command.

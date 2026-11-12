# Orb Motion Playground

This is a standalone macOS 14+ motion study. It adds the `OrbMotionKit` library and
`OrbMotionPlayground` executable to the Swift package without integrating them into
the CodexMeter assistant. It contains no projection beam, dashboard, menu-bar manager,
startup integration, network requests, or usage-data readers in Orb mode. The sibling
[Projection mode](projection-playground.md) adds the second-stage desktop study using
the same executable and retained preview identity.

## Language

Use the menu at the top right to choose **English** or **简体中文**. Both modes share
this choice and update immediately, including window titles, playback commands,
parameter labels, hints, construction phases and accessibility descriptions.
The first launch follows the system language; subsequent selections are remembered
in the fixed preview's isolated preferences. Switching language keeps the current
parameters, selected tab, playback state and timeline progress. Standard macOS
application menus continue to follow macOS.

Projection parameters are also remembered across preview restarts. The language
upgrade seeds the most recently inspected right-edge configuration when no saved
projection configuration exists. It leaves the approved orb defaults intact.

Language-update validation passed 45 focused tests and exported 20 final native
render fixtures across both languages, both themes and all parameter tabs. The
same offscreen session preserves edited parameters and paused playheads during
the language update. Evidence is in `work/playground-language/qa`. Computer Use
was removed during the turn, so these are render previews rather than real desktop
screenshots, and the live language-menu click was not manually verified.

## Run and iterate

From the repository root:

```bash
./scripts/motion-playground.sh
```

Only the playground product is compiled. The helper updates the already authorized
preview in place at `/private/tmp/codexmeter-unified-hud-qa/dashboard/CodexMeter.app`,
retaining `io.github.codexmeter.unified-hud-qa.dashboard` and its isolated preferences
and permissions. It stops the exact resolved executable before replacement, preserves
a CRC-verified ZIP in `build/motion-playground/backups`, verifies the signed package,
and launches one instance. It never replaces `/Applications/CodexMeter.app`.

```bash
./scripts/motion-playground.sh --build-only
./scripts/motion-playground.sh --test
./scripts/motion-playground.sh --stop
```

The build-only executable is `build/motion-playground/OrbMotionPlayground`.
The preview helper intentionally requires the existing authorized preview rather than
creating another application identity. The build and test commands do not need a
running assistant. Command Line Tools are sufficient; the native SwiftPM backend is
used for this environment. No new Swift package dependencies are required.

With full Xcode installed, open `Package.swift`, select `OrbMotionPlayground`, and run
the executable scheme. `EnergyOrb_Previews` in `Sources/OrbMotionKit/EnergyOrb.swift`
provides frozen 0%, 40%, and 100% comparisons at native 60-point size. Full Xcode and
its preview canvas were unavailable on the implementation machine; that canvas has
not been executed here.

## Using the lab

- The live orb defaults to a front-facing 60-point circle. Hover charges it; exit
  reverses from its current progress. The three smaller comparisons are static.
- `1:1`, `2×`, and `3×` change inspection magnification, independently of the real
  diameter parameter. The stage remains dark in either inspector appearance.
- Appearance controls cover diameter, core size, ring weight, tick count, energy
  hue, glow strength, halo radius, and glass opacity.
- Motion controls cover both rotor speeds, breathing period/depth, scan speed,
  charge/release durations, the time curve, and a local Reduce Motion preview.
- Dragging the activation slider pauses every animated clock and directly sets
  progress. Activate and Retract continue from that value in the chosen direction.
- Play/Pause, Reset, Loop, Simulate Hover, and 0.25×/0.5×/1×/2× are live controls.
  Explicit playback commands take over from simulated hover. Actual and simulated
  pointer ownership are combined when the simulation toggle changes.
- Command-Right Arrow activates; Command-Left Arrow retracts; Space toggles playback;
  Command-R resets. Native controls retain their standard keyboard alternatives.
- Defaults restores the appearance/motion parameters and a paused baseline.

## Reusing the component

`OrbParameters` owns the appearance and motion values plus validated ranges.
`MotionTimeline` is independent of windows and drawing. It consumes elapsed time and
stores the actual visible progress, direction, playback state, and ambient phases.
`MotionSample` maps progress into overlapping core, energy-ring, tick-sweep, and
convergence stages. Reverse playback evaluates the same functions with decreasing
progress; it does not start an unrelated exit animation.

`EnergyOrb` renders frozen or externally supplied progress. `AnimatedEnergyOrb`
connects the same retained layer renderer directly to a controller. Both are native
SwiftUI components; the renderer uses Core Animation for composition. Geometry is
built when parameters or bounds change, then frames update retained layer transforms,
brightness and a few glint positions. Native controls observe a separate, deduplicated
10 Hz snapshot; direct scrub and playback commands refresh their values immediately.
An animated orb does not invalidate the SwiftUI inspector on each frame.

`MotionController` owns one monotonic driver. Interactive transitions target 60 Hz;
standby uses a lower cadence. Pausing and scrubbing freeze the playhead and ambient
phases. Suspending or stopping cancels the driver, and resuming starts a fresh clock
baseline so hidden wall time cannot finish an unseen transition. The single-window
demo connects this lifecycle to scene activity and view disappearance.

The rotor phase integrates a speed multiplier from the authored progress curve. At
full activation it runs at 2.8 times the configured standby speed. Reversing does not
reset its angle or velocity; speed returns gradually as progress falls. Breathing
and scanning retain a separate ambient clock. Loop endpoint remainders and complete
cycles are consumed independently of frame partitioning.

Reduce Motion disables ambient rotation, breathing, traveling glints, and automatic
looping. It substitutes a brief light transition, while direct scrubbing remains
available. The system setting cannot be overridden by disabling the local preview.
The visual surface is custom translucent geometry, compatible with macOS 14; it
does not claim macOS 26 Liquid Glass refraction.

## Applied skills

All five requested skills were installed without overwriting existing skills:
`swiftui-microinteractions`, `apple-motion-feel`, `liquid-glass-motion`, `liquid-glass`,
and `animation-patterns`. Their real repository paths were checked, their `SKILL.md`
files read, and `npx --yes skills ls -g -a codex` confirmed all five for Codex.
Canonical files are in `~/.codex/skills`; non-overwriting links in `~/.agents/skills`
make the skills CLI discover them. Newly installed skills enter the automatic Codex
catalog on the next turn; this implementation read the installed files directly.

Applied principles include one presentation-progress owner, interruptible input,
no hover bounce, direct scrub tracking, restrained layered energy, availability
checks, and complete suspension of ambient motion under Reduce Motion. Independent
keyframe/phase loops, UIKit/CoreHaptics samples, iOS-only APIs, web frameworks, and
Metal effects were not needed. UI/UX Pro Max informed native controls, system fonts,
spacing, contrast, and accessibility; its generic web landing-page suggestions were
not applicable to this lab.

## Verification

The targeted Swift Testing suites cover interrupted 40% reversal, re-entry at 30%,
rapid hover changes, exact scrubbing, bounded stage samples, pause/resume, playback
rates, loop remainders, frame-independent rotor integration, parameter validation,
Reduce Motion, lifecycle suspension, cancellation, and controller release.

Actual native-window observations and build/test logs are kept under
`work/motion-playground/qa`. The delegated UI executor uses the fixed preview
identity. Screenshots were shown in the tool conversation; the CUA screenshot API
did not expose a supported file-saving operation, so no saved PNG is claimed.
The available native CUA interface supports clicks and drags but no pointer-move
operation. Real physical hover entry/exit and delivered display FPS therefore remain
manual verification items; simulated hover, intermediate timeline reversal, and
pure state continuity were checked separately. CPU spotchecks are process CPU time
over a bounded interval, not GPU load, power draw, or an FPS benchmark.

Final local checks: the standalone release build and its resource probe passed,
all 19 targeted tests passed, and the same signed preview was used throughout.
Final strict signature/identity verification passed and the preview was stopped,
with zero matching processes remaining. `final-package.json` records matching Mach-O
UUIDs and all 36 section hashes between the build and the preview executable;
whole-file hashes differ because bundling changes the embedded code signature.
The initial native-window rounds caught a low-contrast magnification selector and,
after the renderer migration, a collapsed radial gradient. Both were corrected and
checked again in the actual window. See `round1.md`, `round2.md`, and `round3.md` in
the QA directory for observed interactions and limits.

The retained renderer was introduced because a stack sample showed repeated SwiftUI
layout and native-control updates dominating CPU cost. These bounded foreground
samples include the full debug window at 60 pt and 1×:

| Renderer | Standby | Continuous charge/release loop |
| --- | ---: | ---: |
| Initial Canvas + unthrottled controls | about 38.6% | about 56.3% |
| Retained native layers + deduplicated controls | 1.58% | 21.95% |

Percentages are fractions of **one CPU core**, computed from a three-second process
CPU-time delta. They are spotchecks, not long-term energy results. The loop includes
10 Hz inspector updates and remains more expensive than the ambient-only state.
The counters use Mach time and are converted with `mach_timebase_info`; the owning
[XNU implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c#L6391-L6392)
provides the basis for that unit conversion. The initial standby raw counter was
retained only through its rounded intermediate value, so its percentage is approximate.
JSON measurements and a reusable measurement script are in the QA directory; the
initial stack sample is compressed as `loop-sample.txt.gz`.

CoreGraphics path rendering follows native geometry rather than a 3D camera.
Apple's [Canvas documentation](https://developer.apple.com/documentation/swiftui/canvas)
and [asynchronous rendering reference](https://developer.apple.com/documentation/swiftui/canvas/rendersasynchronously)
were consulted during the initial renderer implementation.


## Launch visibility follow-up — 2026-11-12

The retained preview bundle declares `LSUIElement`, which can leave a running lab
without reliable foreground activation. The standalone executable now adopts the
regular application policy and presents its window on launch, view appearance, and
reopen. Presentation restores a minimized window, moves it to the active Space,
centers it, and requests activation. This changes only the independent demo;
the shared preview identifier and the installed assistant remain unchanged.

The standalone release build and its verification probe passed after this change.

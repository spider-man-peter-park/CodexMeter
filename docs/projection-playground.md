# Projection Playground

The [third-stage JARVIS HUD study](hud-playground.md) now replaces the synthetic
central skeleton in controller-backed scenes with interactive modules. The beam,
approved orb and continuous projection progress are retained. The historical
verification record below describes the second-stage checkpoint.

The second-stage study adds Projection mode to the existing standalone playground.
It does not integrate the prototype into the installed CodexMeter assistant. The
native orb geometry and first-stage animation are reused. The original projection
phase left all five `OrbMotionKit` source hashes unchanged; the subsequent language
update only changes the orb library's accessibility text and language plumbing.

## Start

```bash
./scripts/projection-playground.sh
./scripts/projection-playground.sh --build-only
./scripts/projection-playground.sh --test
./scripts/projection-playground.sh --stop
```

The helper builds only `OrbMotionPlayground` and selects `--projection-playground`.
The Orb/Projection selector changes modes inside the same executable. The retained
preview path remains `/private/tmp/codexmeter-unified-hud-qa/dashboard/CodexMeter.app`,
with identifier `io.github.codexmeter.unified-hud-qa.dashboard`. The application name
in the Dock remains CodexMeter; the new window title is **Projection Playground**.
The preview helper stops the exact resolved process before replacement, preserves
the previous package as a CRC-verified ZIP, and verifies the new signature. It does
not replace `/Applications/CodexMeter.app`, publish a release, or modify usage data.

The fixed preview must already exist. If the temporary directory is removed,
restore its verified archive to that same path before using the helper; it never
creates a replacement identity. Archives are in `build/motion-playground/backups`.

## Language and retained tuning

The top-right menu switches immediately between **English** and **简体中文** for both
Orb and Projection modes. The choice is remembered in the preview's isolated
preferences. The first launch uses the system language. Buttons, parameter groups,
status, hints, timeline phases, skeleton-card captions, window titles and owned
playback commands all use the selected language. Standard macOS application menus
continue to use macOS's language.

Language changes do not reset parameters, selected tabs, controller identity or the
playhead. Projection parameters now survive preview restarts. Before replacing the
running preview, the user's right-edge tuning was read from the native UI; those
values seed a missing saved configuration, including source height
`0.1524739583333333`, beam width `103`, divergence `10`, brightness `0.87`, edge glow
`1`, particle speed `0.79`, scan visibility `0.6`, one volume layer and zero ring
rotation. The remaining projection and approved orb values are preserved.

The language revision passed 45 focused tests, including unchanged animation,
geometry and lifecycle regressions, format signatures, remembered choice and
parameter/playhead preservation. Twenty final offscreen native fixtures cover
both languages, both themes and all five parameter tabs; the fixed preview's
signed binary matches the release build's UUID and all 36 code/data sections.
Computer Use was removed during this turn. These fixtures are not actual desktop
screenshots and do not establish live mouse selection or desktop behavior.
Evidence is in `work/playground-language/qa`.

Full Xcode is not required to build/run. With Xcode installed, open `Package.swift`
and use `ProjectionStage_Previews` for a frozen native view. That Xcode canvas and
the minimum macOS 14 runtime were not executed on this Command Line Tools machine.

## Preserved orb tuning

The accepted live settings were read from the running first-stage UI before its
process was replaced. `ApprovedOrbParameters` preserves this snapshot for startup
and Orb-mode defaults:

| Parameter | Accepted value |
| --- | ---: |
| Diameter / core ratio / ring weight | 70 pt / 37% / 1.79 pt |
| Ticks / energy hue | 48 / 0.51 (about 184°) |
| Glow / halo radius / glass opacity | 98% / 13 pt / 25% |
| Outer / inner rotation | −40°/s / +40°/s |
| Breathing period / amplitude | 4.8 s / 0.09 |
| Scan speed | 42°/s |
| Orb-mode charge / release / curve | 0.72 s / 0.67 s / Smooth |

Projection mode maps the same orb's activation to phase A of the projection
timeline. It does not redraw the orb or change its material, rings, core or colors.
Projection Defaults resets projection parameters while retaining this orb snapshot.
Values edited later in Orb mode are local to that mode; the projection source uses
the explicitly accepted snapshot above.

## Desktop and stage controls

An active desktop projection dims and softly blurs its entire selected display
behind the orb and HUD. The black translucent backdrop uses a native behind-window
visual effect and covers the display's full frame, including the menu bar and Dock
area. Its fade follows the existing activation playhead in both directions; a
retracted, disabled, hidden or stopped projection leaves no backdrop. It ignores
mouse input and cannot become the key or main window. Other displays keep their
normal appearance. The embedded inspection stage does not dim the desktop.

The **Backdrop** parameter tab offers a backdrop switch and live percentage sliders
for overall opacity, black tint and background blur. Opacity at 0% removes the
backdrop; 100% applies the full configured effect. Background blur crossfades the
native material from clear to its full effect. **Backdrop defaults** restores only
these controls, leaving the beam, orb, HUD and current playhead in place. Values are
saved separately and restored on the next launch. Both languages show the current
percentage beside each slider.

Desktop projection starts enabled. The source is a separate 70-point orb near the
left screen edge; the inspector starts on the opposite side so the middle stays
available for the HUD. Left/Right mirrors the source and beam and adjusts the HUD's
small perspective bias. The target remains at the selected display's usable center.
The Display picker can choose another attached screen. Dragging the source snaps
it back to the nearer side on release and retains its vertical position.

Hovering the source expands the projection; leaving reverses from the current
progress. Expand/Retract and the slider allow inspection without holding the pointer
over the source. The slider pauses every animated phase at its selected value.
Play/Pause, Reset, Simulate Hover, and 0.25×/0.5×/1×/2× are available. Loop is an
explicit latched demo: incidental pointer entry/exit does not cancel it. Manual
Expand/Retract and simulated hover take control from Loop. Pause freezes the loop
without changing its configuration. The Last input line reports actual commands.

Turn Desktop projection off to inspect the same renderer in the embedded stage.
Widen the inspector window for a larger embedded study. This mode exposes the same
native source tracking view and uses the same clock and progress values; it does
not create another app or another animation script.

Beam controls cover volumetric length, width, divergence, brightness, edge glow,
particle density/speed, scan-line strength and layer count. Volumetric length changes
the luminous fan; its fine connecting ray continues to the central target so changing
the setting cannot detach the HUD from the source.

HUD controls cover primary radius, auxiliary rings, ticks, radar/rotation speeds,
card count, connector length, halo and total scale. Geometry automatically fits
smaller usable displays while keeping the target centered and clearing the orb.
Cards contain deliberate synthetic waveform/bar skeletons, not live measurements.

## One reversible construction timeline

| Progress | Construction |
| --- | --- |
| 0–15% | Existing orb charges |
| 15–35% | Layered beam extends from the source center |
| 35–45% | Central focal point establishes |
| 45–65% | Primary ring and staggered auxiliary rings trace and grow |
| 65–85% | Connectors trace, card frames assemble and bars reveal |
| 85–100% | Low-frequency radar, orbital points and energy flow become active |

Default expansion is 1.4 s and retraction 1.25 s. All geometry and stage weights are
functions of one normalized `ProjectionTimeline.progress`. Retraction evaluates the
same functions with decreasing progress. No view insertion, target-value reset, or
independent exit sequence is required for reversal at 42%, re-entry at 31%, or rapid
hover changes. Beam particles combine progress and a continuous signed flow phase;
the phase does not jump when the direction flips, and its opacity envelope conceals
orbital wrapping at either end. Rotor and flow integration consume endpoint remainders
and complete cycles independently of frame partitioning.

## Modules and lifecycle

- `ProjectionConfig`, `ProjectionSample`, `ProjectionTimeline`: bounded settings,
  deterministic construction stages and bidirectional time.
- `ProjectionAnimationController`: one monotonic driver, 60 Hz transition / 30 Hz
  ambient targets, pause/scrub/reset/speed/loop and Reduce Motion.
- `ProjectionBeamView`, `CentralHUDView`, `ProjectionSceneView`: retained native
  layers with disabled implicit animation; no WebView, shader or 3D engine.
- `ProjectionOrbInputView`: native active-always tracking and drag handling, using
  the existing `OrbLayerView` for all source drawing.
- `ProjectionDesktopController`: retained nonactivating source, backdrop and scene panels, screen changes,
  edge positioning, sleep/hide suspension, and teardown.
- `ProjectionDebugPanel`: native controls with a separate deduplicated 10 Hz
  inspector snapshot; direct commands and scrubbing update immediately.

The decorative beam/HUD panel ignores all mouse events; neither floating panel can
become key or main. Hover and render paths contain no application-activation call.
The debug window activates on an explicit launch/reopen. The panel objects are reused
across hover cycles rather than created and destroyed. Sleep or hiding the app freezes
the clock and panels; resuming starts a fresh timestamp baseline. Closing/leaving the
projection mode stops the desktop controller. Ordinary background application focus
does not suspend the source, so it can accept hover while another app is in use.

Reduce Motion stops ambient loops, particles, radar and perspective travel, replaces
kinetic assembly with brief state feedback, and disables automatic looping. No
global accessibility, appearance, permission, or system preference is changed.

## Verification and limits

The release build and probe passed. All 38 targeted tests passed: 19 existing orb
tests and 19 projection tests. They cover phase order, 42% exit/31% re-entry,
rapid retargeting, reverse particle phase, pause/scrub, asymmetric cycles, speeds,
invalid inputs, left/right and negative-origin display geometry, source-to-center
alignment, click-through/nonactivating panel configuration, native hit regions,
pointer/loop ownership, and driver cancellation/lifetime.

Actual native-window reviews inspected stages 42/45/65/80/100%, left/right embedded
projection, changing HUD radius and fan length, partial reversal and re-expansion,
Reduce Motion, speed controls, and the accepted 70-point Orb-mode values. A clipped
0.25× label was widened and checked again. A loop cancellation found during CPU
sampling was corrected by making demo ownership explicit and preserving the app
session as a `StateObject`; a regression test and more than ten seconds of actual
loop observation confirmed continued playback. The final loop was still checked
and progressing after its CPU sample.

Evidence is in `work/projection-playground/qa`, including source hashes, test/build
logs, and review notes. Screenshots were displayed inline by Computer Use; no PNG
export is claimed. Current CUA cannot select/capture the separate borderless desktop
panels or the full desktop, and a documented safe drag attempt failed with
`windowNotFoundAtPosition`. Therefore physical hover/drag, full desktop compositing,
cross-application focus retention and click-through are **not manually verified**.
The panel status row reads actual `isVisible` and `isOnActiveSpace` properties;
`Source on · HUD on · active Space` is not an occlusion or interaction measurement.
Native tracking/geometry and window policies have separate automated coverage.
Delivered display FPS, GPU/power draw, Intel and macOS 14 execution were not measured.

| Three-second process CPU spotcheck | One CPU core |
| --- | ---: |
| Standby, approved source running | 2.06% |
| Fully projected, ambient flow running | 6.63% |
| Continuous bidirectional demo, verified before/after | 27.64% |

These bounded samples include the debug window and use `proc_pid_rusage` Mach-time
deltas converted by `mach_timebase_info`, not fabricated FPS or energy values. The
earlier cancelled-loop sample is explicitly invalidated and excluded. They are not
long-term performance guarantees. The runtime creates no new app identity, and no
commit, push, public release or Homebrew change is part of this task.


Final package verification checked the strict signature and identifier, matched the
Mach-O UUID and all 38 code/data sections against the release build, and revalidated
the previous-package ZIP. Automated QA ended with zero preview processes and CUA
confirmed closure. The same verified package was then launched once in Projection
mode for the user's existing request to inspect the motion, and left running.

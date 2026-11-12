# JARVIS HUD Playground

This third-stage study extends the independent Orb / Projection executable. It does
not integrate with the installed assistant, its data ledger, or an AI service.

## Run

```sh
scripts/hud-playground.sh
scripts/hud-playground.sh --build-only
scripts/hud-playground.sh --test
scripts/hud-playground.sh --stop
```

The normal launch starts with the HUD projected for inspection. Use Retract/Expand
to exercise the existing continuous playhead, or move into the source and then
toward the HUD. The fixed preview remains
`/private/tmp/codexmeter-unified-hud-qa/dashboard/CodexMeter.app` with identifier
`io.github.codexmeter.unified-hud-qa.dashboard`. Its prior package is retained as a
verified ZIP before replacement. The installed `/Applications/CodexMeter.app` is
outside this prototype's scope.

The existing top-right language menu controls both English and Simplified Chinese.
HUD settings persist separately from the accepted orb and projection parameters.

## State at entry

The first two phases already had the approved native orb, source-to-center beam,
six construction stages, deterministic scrubbing, interruption and reversal, loop,
Reduce Motion, source dragging and display selection. The HUD consisted of rings
and synthetic skeleton cards. All decoration was click-through; there was no
interactive content, native telemetry provider, module selection/detail, or safe
pointer handoff from the edge source. Physical hover/drag, desktop composition and
multiple-monitor hardware behavior had verification gaps, not completed manual
certification. Those gaps are explicitly distinguished from the implemented code.

## Content and interaction

The central instrument has positioning ticks, two slow opposing rotor bands, CPU
and memory arcs, a directional interaction scan and a detail/overview area. Six
asymmetric modules provide System, Performance, AI, Network, Activity and Controls.
Curved telemetry panels, cut corners and short connector paths share design tokens
with readable system fonts. Modules support idle, hover, selected, expanded and
disabled states. Click a module or core sector for detail; use the central Back
action or Controls to return. Unrelated modules reduce emphasis without replaying
the projection. Controls pause decoration, cycle density and open/close detail.

The HUD tab contains Layout, Style, Interaction and Dynamics controls, including
module visibility/disable, arrangement, sizes, spacing, color, material, line/glow,
type size, scan, opposing rotation, feedback duration/damping, pulse, exit delay,
transit grace and state simulation. Global transport retains scrubbing, speed and
loop; the rapid-entry/reversal command exercises intermediate direction changes.
Open HUD inspection provides a large interactive window. While it is open the
desktop input surfaces and embedded miniature are disabled, leaving one owner of
the shared interaction policy; closing it restores the previous desktop setting.

Pointer policy uses idle/opening/previewing/interacting/closing. It selects targets;
the existing time integrator retains actual progress. Source exits allow a bounded
transit corridor and configurable delay. HUD entry maintains the projection;
outside departure retracts it. Explicit transport commands retain ownership until
a fresh pointer entry, and manual closing suppresses immediate reopening under a
stationary pointer. The full decorative panel always ignores mouse input. Only
tight core/module panels receive input, with shape-aware hit regions and passive
mouse tracking. No full-screen capturing window or keyboard event tap is used.

Each module maps connector, border, content and chart strokes from the same global
progress, with small deterministic offsets. Reverse traversal removes content,
outlines and connectors before the core/beam. Decoration has a separate pause;
Reduce Motion freezes ambient movement and keeps brief state feedback. Input-only
views skip drawing work and control inspectors avoid animation-rate subscriptions.

## Data

Native providers use Mach host CPU deltas, memory page accounting, physical RAM,
system uptime, device/OS/time, and 64-bit physical-interface byte counter deltas.
Network means local active `en` interfaces, excluding loopback/tunnel duplication;
it does not assert Internet reachability. First samples, resets and stale deltas
are unavailable. GPU is unavailable rather than estimated. Sampling is every two
seconds while HUD content is visible, omits disabled/hidden module telemetry, and
keeps at most 60 history values. It stops on close, hide/sleep and full retraction.

AI and Activity use an isolated Mock provider and are visibly marked Mock. No AI
requests are made. Render fixtures additionally mark **all** metrics as simulated;
the exporter separately samples native counters and records their provenance.

## Verification boundaries

Build logs, focused tests, native component action probes, layout/timeline renders,
package checks and process samples are stored in `work/hud-playground/qa`.
Computer Use is unavailable in this session. Generated native fixtures are not
desktop screenshots and programmatic view actions are not physical mouse tests.
Actual cross-application focus, physical source-to-HUD travel, desktop composition,
external displays, Retina settings, long standby and delivered 60fps remain manual
hardware verification items. The code targets 60 Hz transitions and 30 Hz ambient;
these target rates are not measured display frame rates.

Final local verification passed 66 focused tests. Eleven final HUD render fixtures
cover both languages, three densities, partial construction, selection/detail,
Disabled and Reduce Motion; four additional inspector fixtures cover both themes
and languages. Native component action probes passed, and separate live provider
diagnostics returned CPU, memory and upload/download readings with GPU unavailable.
The fixed preview passed strict signature/identifier checks and matched the final
build's UUID and all 37 file-backed code/data sections. Approved orb files, beam
renderer and projection configuration match their baseline hashes.

Three-second process CPU spotchecks for the final package were 6.98% of one core
in standby and 10.26% projected, including the debug window and local telemetry.
These are bounded samples, not delivered-FPS, GPU, energy or long-idle guarantees;
the earlier pre-window-order sample is excluded. The helper confirmed zero render
test processes before runtime checks and exactly one final preview instance. The
preview is left projected for user inspection. Saved Chinese and projection values
were compared exactly after launch and retained. No commit or publication occurred.

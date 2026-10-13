# Interactive agent vs configured screenshot runner

One matched paired-output experiment on 2026-10-11. This compares agent-driven
UI navigation against an existing XCTest scenario, not human tapping speed.
Both reuse the same binary SHA256, fixture, Screener harness, collector and PNG
preparer; neither builds the app.

## Matched deliverable

CityChain main + Atlas, portrait + landscapeLeft, en-US/light, iPad Pro 13 M5
iOS27.0, 2064×2752 / 2752×2064 at2×. Each run produces4Screener RGB16 and
4system RGB8 PNGs. Source executable SHA256 and the full asset identity/geometry/
bit-depth sets were asserted equal. Both packages are complete, have closed
consecutive traces and pass decoded pixel-preserving PNG preparation.
The comparison contact sheet of all16PNG images was inspected after both timers.
Desired states, language and orientations match. This is not a pixel-identity test.

System reference implementations differ: interactive uses `simctl io screenshot`,
automated uses XCUIScreen. DeviceInteraction screenshots are1× and were only
used to inspect the UI in the successful interactive run. No upscaling was used.

## Results

| Metric | Interactive agent | Automated runner |
| --- | ---: | ---: |
| Successful full invocation |111.571s|78.744s|
| PNG preparation |13.095s|17.404s|
| Agent-visible nested tool calls during run |33|2|
| functions.exec wrappers |14|2|

**32.827s less elapsed time (29.42%;1.417× speed ratio)**.
**31 fewer agent-visible tool calls (93.94% reduction)**.

Manual calls:6DeviceInteractionSynthesize,2Start/EndSession,4view_image,
16exec_command,5write_stdin. Four taps and two orientation events were selected
from fresh AX hitPoints. There were no UI retries. These tool calls include the
visual observations needed to choose the next interaction; final contact-sheet
review/reporting is excluded.

Automatic counted calls: one exec_command to launch the configured runner, one
write_stdin to collect completion. Internal subprocesses remain recorded in
[auto metrics](auto-metrics.json); they are not model/tool round trips.
Only `CityChainScreenshotTests/testScreenshots` executed and passed(32.186s
inside a40.698s xcodebuild command). Runtime opt-out was excluded from this pair.

Both start cold with install/setup. Manual shutdown overlaps PNG preparation;
auto shutdown follows it(3.265s), so lifecycle scheduling is not identical.
Manual setup9.523s, interactive capture/orchestration88.740s, collection0.083s;
four checkpoint helpers total8.456s. The automatic setup/install path also
takes longer here. A single pair and cache/order effects do not establish a
statistical or universal speedup. Source/docs integration and final review are
outside both timers. No token usage, billed cost or human effort was measured.

## Failed attempts and environment costs

The first interactive attempt failed: DeviceInteraction's screenshotPath, despite
its full-size description, encodes point dimensions at1×. Native assertions and
collector rejection prevented delivering those files. The failed attempt spans
14:32:01–14:34:44UTC(~163s), with subsequent diagnosis before the successful
run14:36:05.847–14:37:57.418UTC. About5m56s elapsed from the first interactive
start to the first completed native package; this exploration cost is separate
from the111.571s successful-repeat comparison.

The first automatic launch was rejected by disk preflight before UI execution.
A904MiB auxiliary GUI compiler/index cache was removed; source, canonical app
products and screenshot evidence were preserved. The benchmark-only temporary
config uses1GiB minimum headroom with an existing Simulator and binary, and
selects only the screenshot test. Standard capture.json remains at3GiB. Cache
cleanup/reporting gaps are outside the78.744s successful timer.

## Evidence

- [Comparison summary](comparison.json)
- [Manual metrics](manual-interactive-metrics.json) and [manifest](manual-manifest.json)
- [Failed manual attempt](manual-failed-attempt.json)
- [Automatic metrics](auto-metrics.json) and [manifest](auto-manifest.json)

Local outputs remain ignored:
`output/interactive-benchmark-20261011T143542Z`,
`output/20261011T144017900118Z`; galleries are each review.html.
`output/ab-review/comparison.jpg` shows all16prepared images side by side.

## Interpretation

On this small four-state matrix, repeat-run wall-clock savings are moderate.
The larger measured reduction is in agent-visible orchestration calls. Automation
also enforces checkpoint order/native geometry/closed traces without asking the
agent to inspect each intermediate screen. This does not quantify token savings
or amortize integration cost; those require separate accounting.

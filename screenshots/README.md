# Screener screenshot example

Experimental integration, separate from App Store delivery.

## Run

```sh
rtk proxy make screenshots-screener
rtk proxy make screenshots-screener SCREENSHOT_ARGS='--simulator UUID --skip-build'
rtk proxy python3 screenshots/tools/run.py --prepare-output screenshots/output/RUN
```

The default command generates the canonical CityChainApp project, builds the
`ScreenerScreenshots` configuration in `.build/DerivedData`, then runs only
`CityChainScreenshotTests`. Without an explicit Simulator it creates/reuses its
owned matching profile. Never pass a personal Simulator without intending to use it.
The runner does not erase devices or upload assets.

## Integration boundaries

- `SCREENER_SCREENSHOTS` compiles the hidden window probe; Simulator, runtime flag
  and valid run UUID are additionally required to activate capture.
- Isolated bundle: `com.soundblaster.citychain.screenshots`.
- The existing Debug fixture loads six route cities and a Springfield draft.
  No provider request or live AI generation is needed.
- SpecificationCore owns the app readiness decision: loaded snapshot, no
  submission in flight, no fixture error. Main/Atlas presentation is observable.
- The app-specific capture adapter and readiness spec live beside CityChainPage
  in its FSD slice; the generic runner stays outside app source. This avoids a
  pages-to-shared upward dependency while keeping capture mechanics flag-gated.
- XCTest taps City atlas and Done, asserts visible English content, requests
  acknowledged Screener checkpoints and captures system references.
- The runtime opt-out test launches the flagged binary without activation and
  verifies no capture directory is created. Normal Debug/Release source excludes
  the probe. No Release build was executed for this experiment.

Generic tools/adapters were copied from Screener's
`screener-app-store-screenshots` skill. `tool-provenance.json` identifies their
source SHA256. Keep app navigation, fixture and policy here; update copied tools
explicitly and refresh their provenance when adopting a new skill version.

## Verified matrix — 2026-10-11

| Dimension | Checked |
| --- | --- |
| Device | iPad Pro 13-inch M5, 12GB Simulator |
| OS / SDK | iOS 27.0 / Xcode 27.1 |
| Language / theme | en-US / light |
| Orientation | portrait, landscapeLeft |
| Checkpoints | main, Atlas sheet |
| Native pixels | 2064×2752, 2752×2064, 2× |
| Capture | 4 Screener RGB16 + 4 XCUIScreen RGB8 PNGs |

First successful run: `output/20261011T141214872504Z`.
Both scoped UI tests passed. Traces ended with consecutive sequence numbers;
PNG preparation verified decoded pixel equality, preserved native dimensions
and RGB depth, and removed only opaque alpha. All eight prepared images were
reviewed in a contact sheet: desired main/sheet states, English content and
orientation are present. The system references retain status chrome; UIKit
captures omit it. Neither backend required screen-recording permission.

Versioned evidence: [first manifest](validation/2026-10-11/first-manifest.json),
[first metrics](validation/2026-10-11/first-metrics.json). Raw files, traces, PNGs,
logs and xcresult remain in ignored `output/`; open each run's `review.html`.

## Cost and limits

First successful invocation: **291.787s** total, including **192.810s** build,
**63.473s** UI-test command and **15.287s** preparation. Other time includes
boot/install/shutdown, collection and orchestration. This is four UI states,
not eight distinct states.

First app integration before the first attempted build took about **9m23s**
(13:47:50–13:57:13 UTC). End to end from integration start to first complete
package was about **29m17s**, including macro trust, disk preflight failures,
cache cleanup, debugging and documentation work. Skill extraction work was
separate and is not included. The buildless repeat is measured below.

The first build was blocked by changed SpecificationCore macro trust; the user
authorized specific target trust through Xcode. No global bypass was enabled.
Later preflight failures retained existing batches until rebuildable compiler
caches were removed. Historical failed outputs remain preserved.

Five concurrency diagnostics originate in existing CityChainScoutMapUITests;
Xcode also reported two skipped AppIntents metadata extractions. No diagnostic
was emitted for the added screenshot sources. Unrelated tests were compiled
with the target but were not executed.

Map tile readiness, pixel identity across map/network updates, dark mode, other
locales, iPhone/Duo, physical devices, Release behavior and Apple acceptance
were not established. The settling guard checks window geometry and app readiness,
not arbitrary network completion. Screenshots are candidates for review.
Model-token savings cannot be inferred from elapsed time or frame count.

## Repeat without build

`output/20261011T141744724911Z`: **87.564s** total, including **55.579s**
UI-test command and **13.812s** PNG preparation. Both UI tests passed again.
The same binary SHA256 and matrix were reused. This run started with the
Simulator shut down and includes boot/install/shutdown; it needs no interactive
UI tool calls after command launch.

Evidence: [repeat metrics](validation/2026-10-11/repeat-metrics.json),
[repeat manifest](validation/2026-10-11/repeat-manifest.json).

Compared with the 291.787s successful build invocation, this removes 204.223s
(~70%) of elapsed time. This measures build reuse, not a controlled comparison
against manual capture. The more useful workflow gain is replacing repeated
launch/rotate/navigate/capture/export operations with one command. A small number
of visual reviews remains necessary. No model-token savings were measured.

Preparation-only recovery completed in **12.873s** without building or launching
the app; raw hashes and closed traces were checked again. The original capture
metrics SHA256 remained unchanged. [Recovery metrics](validation/2026-10-11/preparation-metrics.json).

## Matched interactive comparison

A [one-pair A/B experiment](validation/2026-10-11/ab/README.md) measured
111.571s interactive versus78.744s configured automation for the same8native
PNGs, without builds:32.827s(29.42%) less elapsed time and33→2agent-visible
tool calls. This compares an equipped agent with a ready UI-test runner, not
human speed. Failed1×capture and disk-preflight attempts are recorded separately.
No token or billed-cost savings were measured.

## Review fixes (2026-10-11)

The opt-in `project.screenshots.yml` adds the `CityChainScreenshotApp` and
`CityChainScreenshotUITests` targets and the `CityChainScreenshots` scheme to the
same canonical project. Only that app target links ScreenerKit. Ordinary
`project.yml` does not declare Screener at all; regenerate with
`xcodegen generate --spec project.yml` before ordinary development/release work.
The runner now preserves complete language identifiers and replaces deleted
owned simulators; an invalid explicit `--simulator` still fails. Tool provenance
is refreshed. The app-specific harness is colocated in the page slice so FSD lint sees only
valid dependency direction; its `UIViewRepresentableContext` type is explicit to
avoid resolving SwiftUI `Context` to the page preview type. Historical benchmark
evidence applies to the earlier executable and architecture; no new app execution
was performed for these changes.

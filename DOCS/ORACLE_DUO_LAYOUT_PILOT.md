# Magic 8 Ball: Duo layout pilot

Status: opt-in implementation. The default layout is unchanged. The app still
supports iOS 26; active division geometry is available on iOS 27.1 and later.
Build the project with Xcode 27.1, as configured in CI.

## Enable and roll back

In the **OracleBallApp** scheme, add this Run environment variable:

```text
ORACLE_DUO_LAYOUT_PILOT=1
```

Alternatively, add these launch arguments:

```text
-oracleDuoLayoutPilot YES
```

The environment value takes precedence over UserDefaults. Values `1` and `true`
enable the pilot; any other supplied environment value disables it. With neither
an environment override nor an enabled UserDefaults value, the flag is off.

The root view samples the flag into State for the lifetime of the page. Enabling
or disabling it requires relaunching the app and does not swap a live renderer
during an answer. To roll back, set the environment value to `0` and relaunch,
or remove the environment override and the launch arguments if no enabled value
was saved in UserDefaults.

`ORACLE_HAS_RESERVED_REGIONS` is a separate **compile-time** condition on the
OracleBallApp target. It enables the SDK adapter; it does not enable the pilot.
The adapter checks iOS 27.1 availability before calling the API. An older SDK
can compile the ordinary adaptive path by removing that build condition, but
the committed configuration and CI use Xcode 27.1.

## Composition and policy

`OracleLayoutPolicy` lives in `OraclePresentation`. It uses named
`PredicateSpec` rules and an ordered `FirstMatchSpec` with a single-pane fallback.
The policy receives dimensions and environment facts; SwiftUI owns coordinates,
focus, presentation, and rendering.

| Priority | Layout | Condition and composition |
| --- | --- | --- |
| 1 | Book | Active vertical division; ball fits before it and controls fit after it. Ball on the left, question and history on the right. |
| 2 | Tabletop | Active horizontal division with the same fit rules. Ball above, controls below. |
| 3 | Focused after fold | Split content cannot fit; use the region after the fold if it fits controls or has at least as much area. |
| 4 | Focused before fold | Remaining active division cases. Both children occupy the usable region before the fold. |
| 5 | Expanded panes | No active division, regular width, at least 760 pt wide and 360 pt resting height, ordinary Dynamic Type sizes. Ball left, controls right. |
| 6 | Single pane | Remaining windows. Ball above the scrollable controls. |

The pilot thresholds are 160 pt for the ball region and 280 × 180 pt for the
controls region. These are initial product choices, not platform guarantees.
There are no device-name checks or hinge-angle thresholds. The adapter uses
active `.division` reserved regions in fixed physical coordinates; an inactive
or out-of-viewport division does not select a fold layout.

The current viewport already excludes the keyboard safe area. A separate current
background GeometryReader inside a keyboard-ignoring region supplies resting
height to keep ordinary wide
composition stable while typing. Neither keyboard height subtraction nor a
historical maximum window size is used. Active fold fit is evaluated against the
currently usable regions, so a keyboard that consumes the lower tabletop region
moves the composer into the usable region above the fold.

## Continuity and interactions

- The root owns one `OraclePageModel`, including the draft, request, answer, and
  history. Layout changes do not submit a question or replace that model.
- One `OracleBallViewport` and one composer remain in stable structural positions.
  Only their frames and positions change; renderer State and field focus remain
  attached to those children.
- When the ball becomes too small to show, it remains mounted and is paused.
  The controls show the answer as text and remain scrollable.
- History appears inline in expanded, book, and tabletop arrangements when space
  permits. It hides while a bottom-attached software keyboard is visible or an
  accessibility text size is selected. History remains available in the info sheet.
- Selecting inline history opens the existing pipeline detail. Repeat and delete
  use the existing model actions. Settings, API credentials, offline fallback,
  widget links, and scene lifecycle use the existing behavior.
- No policy branch directly changes keyboard focus or starts a request.

## Local evidence

On 2026-10-02:

- `swift build --target OraclePresentation` passed.
- Xcode compiler diagnostics reported no issues in `OraclePage.swift` and
  `OraclePilotPage.swift`; the new view files also passed a Swift syntax parse.
- FSD architecture lint v0.4.0 passed for `.fsd-oracle.yml` with no errors or warnings.
- `git diff --check` passed.
- The complete OracleBallApp build stopped before compilation because Xcode
  requires renewed approval for `SpecificationCoreMacros` at the resolved 2.1.0
  revision. No macro trust record or global validation setting was changed.

No tests or runtime/device checks were run for this pilot. CI already builds
OracleBallApp with Xcode 27.1; its results are separate from these local checks.

## Remaining runtime evaluation

These scenarios are the next evaluation step, not a record of completed checks:

| Scenario | Expected result |
| --- | --- |
| Flag off on iPhone and iPad | Existing layout and interactions. |
| Flag on, narrow or reduced window | Single pane; question and status reachable by scrolling. |
| Wide iPad / flat Duo | Ball left, controls and optional history right. |
| Vertical active division | Book arrangement; interactive content avoids the fold. |
| Horizontal active division | Tabletop arrangement; composer below the fold. |
| Tabletop with bottom keyboard | Composer moves above the fold when the lower region cannot fit it. |
| Hardware, floating, or split keyboard | Fit follows usable geometry; focus alone does not hide history. |
| Rotate or fold with a draft and pending answer | Draft, focus, request, and renderer persist; one result is delivered. |
| Accessibility text size / short viewport | Scrollable controls; text answer when ball cannot fit. |
| Open settings or pipeline detail during animation | Scene pauses according to sheet visibility and resumes on dismissal. |

Implementation references:
[Duo examples](https://github.com/artemnovichkov/iPhone-Duo-by-Examples), especially
`Examples/TabletopExample.swift` and `Examples/AvoidDivisionExample.swift`.
The stable composition and current-window measurement also follow the lessons
used for City Chain's adaptive screen. Compile success alone does not establish
fold-transition, keyboard, accessibility, or rendering behavior.

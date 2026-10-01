# CityChain adaptive layout specification

## Status

Implementation specification for iPhone, iPad, and iPhone Duo. The Duo notebook/tabletop layout is a required scenario. The first implementation follows this contract. Physical-device layout and transition validation remain pending.

## Goals

- Keep CityChain usable across compact and expanded windows.
- Choose layouts from available space and the active Duo division, not device identity or guessed pose.
- Preserve one game state as content moves between layouts.
- Use SpecificationCore for meaningful layout policy; keep geometry and rendering in SwiftUI.
- Retain a focused fallback whenever the richer layout cannot fit.

## Platform and source context

The project targets iOS 17.0. New fold-aware APIs must be availability-gated; this work does not raise the deployment target. The 27.1 API is also compile-time gated by SDK, so Xcode 27.0 builds the ordinary adaptive fallback while Xcode 27.1 builds enable active-fold layouts.

Apple recommends adapting to the space and size classes reported by the system instead of branching on a physical pose. When the OS exposes a fold division or reserved region, the layout can keep important content clear of it. Environments without fold information need a useful fallback.

References:

- [Designing for iPhone Duo — Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [Layout — Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Strike a pose with adaptive layouts — Apple Tech Talk](https://developer.apple.com/videos/play/tech-talks/111463/)

Investigation findings to recheck against current source before implementation:

- CityChainPage owns CityChainLayoutSpec and selects an expanded atlas arrangement from size classes, width, and Dynamic Type.
- The expanded-layout result also influences map presentation style; separate these decisions if they represent different policy.
- CityAtlasMapView selects a vertical city list or horizontal chips from scene size classes. A nested pane needs its own measured width.
- GameBoardWidget defaults to a vertical route list and has a local horizontal-filmstrip toggle.
- The city composer uses safeAreaInset at the bottom while the main content scrolls.

## Layout decision boundary

The view layer gathers typed environmental facts and measures its local container. A pure SpecificationCore policy evaluates those facts and returns a semantic layout plan. SwiftUI applies that plan, owns geometry, and calls platform APIs.

The policy must not read SwiftUI environment values, inspect geometry, present sheets, mutate game state, or animate views. Do not wrap every rendering-level if statement in a specification. Use specifications for product decisions such as whether atlas and game share space or whether exploration content yields while typing.

### Proposed semantic plans

CityChainLayoutPlan should describe:

- singleColumn: focused game in one scrollable column.
- expandedPanes: atlas and game together when both fit their minimum readable widths.
- foldAwareBook: two side-by-side regions around an active vertical division.
- foldAwareNotebook: exploration above and game below an active horizontal division.
- focusedBeforeFold / focusedAfterFold: one game pane confined to a usable region when a shared layout cannot fit.

Names are provisional and should follow existing project vocabulary.

### Input facts

Create an immutable, Sendable context from facts such as:

- Available content width and height after system safe-area treatment.
- Horizontal and vertical size classes.
- Whether the Dynamic Type size requires the accessibility layout.
- Active division axis reported by the OS: vertical, horizontal, or none.
- Measured dimensions of the available regions.
- Whether regions meet their minimum readable dimensions.
- Keyboard visibility and remaining space for the active turn.

Keep actual frames in the SwiftUI adapter for placement and clipping. Pass the semantic division axis and relevant dimensions to the policy. Do not subtract safe areas twice.

### Evaluation

Use DecisionSpec or an ordered FirstMatchSpec with documented priority and a singleColumn fallback. Ensure predicates are mutually exclusive or intentionally ordered.

The existing 700-point width check is a baseline, not a device or pose contract. Derive final thresholds from minimum readable pane sizes and check values just below and above each threshold. Keep map presentation style in a separate policy if it is distinct from content arrangement.

## Required scenarios

### Compact phone and Duo outer display

Show focused game content in one column. Keep the turn prompt and city composer available; place route and city suggestions according to available height. The map remains reachable through its existing action. Secondary content may move or yield when space is constrained.

### Flat iPad and Duo inner display

Show atlas and game side by side only when each local region meets its minimum readable width. Otherwise choose singleColumn. Preserve the same game model, current draft, selected city, and pending Scout response across arrangement changes. Scrolling one pane must not unexpectedly scroll the other.

### Duo book fold: vertical division

Treat the active vertical division as a boundary between panes. Keep text, controls, and important map markers clear of the division. If either pane is too narrow, collapse the atlas into its existing navigation action and keep the game usable.

### Duo notebook/tabletop: horizontal division

Treat the active horizontal division as a boundary between an upper exploration region and a lower play region. In the provided concept, the upper part shows the map and Scout/city context; the lower part contains the turn prompt, suggestions, route summary, and composer. Keep the current turn visible and actionable below the fold.

While typing, let secondary exploration yield first if the lower region needs space. Keep the active turn and composer usable above the keyboard. If they cannot fit together, fall back to a scrollable focused game layout. Do not hard-code hinge angle, device dimensions, or a named pose. Use division facts supplied by the OS and retain a single-column fallback when they are unavailable.

## Component-level rules

- Choose the atlas vertical list or horizontal chips using the atlas pane’s measured width, not only the app scene size class.
- Keep vertical route history as the default in a narrow game pane. Retain horizontal filmstrip as an explicit option until reviewed in these layouts.
- Preserve existing ViewThatFits alternatives for local rendering unless the choice represents a product policy.
- The Scout overlay must not obscure the composer, active turn, or essential map controls.
- Keep toolbar actions available in compact and expanded layouts using standard adaptive behavior.

## Accessibility and motion

- Use a focused single-column layout when panes cannot support accessibility Dynamic Type.
- Keep VoiceOver order aligned with the visual sequence: exploration context, active turn, suggestions, composer.
- Respect Reduce Motion for route and layout transitions.
- Keep controls reachable by touch, keyboard, and assistive technologies in every arrangement.

## Acceptance criteria

### Policy cases

Cover these cases in pure layout-policy tests:

- Compact width selects singleColumn.
- Expanded dimensions select expandedPanes only when both panes fit.
- Accessibility Dynamic Type selects a readable fallback.
- A vertical active division selects foldAwareBook when both regions fit, otherwise singleColumn.
- A horizontal active division selects foldAwareNotebook when the lower play region fits, otherwise a focused fallback.
- Keyboard visibility preserves the active turn and composer while allowing exploration to yield.
- Missing fold information selects a valid non-fold-aware plan.
- Width and height values immediately below and above each minimum threshold.

### UI matrix

| Device and state | Expected behavior |
| --- | --- |
| iPhone portrait, keyboard hidden | Focused single-column game |
| iPhone portrait, keyboard shown | Active turn and composer usable; secondary content may yield |
| iPhone landscape | Readable arrangement follows available dimensions |
| iPad portrait and landscape | Shared atlas/game panes only when both remain readable |
| iPad Split View and Stage Manager | Decisions follow actual window dimensions |
| Duo outer display | Focused single-column game |
| Duo inner display, flat | Expanded panes when they fit, otherwise single column |
| Duo inner display, book fold | Fold-aware vertical panes or focused fallback |
| Duo inner display, tabletop fold | Exploration above, turn and input below, or focused fallback |
| Duo tabletop with keyboard | Lower play region remains usable; exploration yields first |

Also verify that layout changes preserve an unfinished draft, selected atlas city, route, and pending Scout response.

## Implementation sequence

1. Recheck current CityChain source and separate content arrangement from unrelated presentation decisions.
2. Define the typed layout context, semantic plan, ordered SpecificationCore policy, and fallback.
3. Add policy tests for scenarios and threshold boundaries.
4. Render plans in CityChainPage and size nested atlas components from their own containers.
5. Add fold-aware arrangement using OS APIs behind availability checks.
6. Add tabletop keyboard priority and preserve game state during transitions.
7. Walk the UI matrix on environments that expose each configuration; record OS and runtime versions.

## Initial implementation and measurements

The pure rules live in [CityChainLayoutPolicy.swift](../Sources/CityChainPresentation/CityChainLayoutPolicy.swift), in a separate CityChainPresentation package target. The [policy tests](../Tests/CityChainPresentationTests/CityChainLayoutPolicyTests.swift) cover size boundaries, fold priority, keyboard-constrained geometry, accessibility, and map presentation.

Initial tuning values, subject to device review:

| Requirement | Value |
| --- | --- |
| Minimum atlas pane width | 320 pt |
| Minimum game pane width | 340 pt |
| Flat expanded window width | 714 pt: both panes plus 18 pt gap and 18 pt outer insets |
| Flat expanded window height | 420 pt |
| Notebook upper exploration height | 200 pt |
| Notebook lower play height | 300 pt |
| Single-column height for the full scenic route | 500 pt |
| Atlas width for vertical visited-city history | 320 pt; accessibility text always uses the vertical list |

CityChainPage reads active reserved regions with the iOS 27.1 API behind an availability check. The existing iOS 17 deployment target is retained. No fold metadata means ordinary space-based layout.

The adapter uses the viewport already reduced by the keyboard safe area for fold regions and pane frames. It also measures the resting height with the keyboard hidden; the flat two-pane arrangement and the full scenic route are judged at rest, so focusing the composer never rebuilds the screen or unmounts the route card mid-animation. Keyboard visibility is never inferred from input focus, and keyboard height is never subtracted a second time. When the lower notebook region no longer fits play controls, the policy gives the game the larger usable region; an active fold is never treated as ordinary uninterrupted space.

The game keeps a stable identity while frames change. The atlas is built only while a plan shows it, so single-column phones do not lay out or animate an invisible map; its selected city is page-owned and survives. The game model, input binding, focus binding, selected city, and pane-local state retain their owners. Shared-map and short layouts replace the full scenic route with the turn prompt and compact Scout feedback. Scout opens the map only in poses that hold a map and never while a submitted turn is being checked, using the shared interaction specification. Scout stays one button whose tap is switched on and off, so pose reactions keep playing.

The notebook atlas keeps the map above selected-city details, so selecting a marker still exposes its state and capital status. Its full history remains available through the map action. Other atlas layouts choose history presentation from the local pane width and include cities without known coordinates.

Runtime follow-up remains the complete UI matrix above, especially keyboard transitions across a horizontal fold, VoiceOver order, and Dynamic Type readability. Unit tests and compilation do not establish those visual results.

## Verification record

2026-10-01: the CityChainApp iOS Simulator build passed with Xcode 27.1. All 11 CityChainPresentationTests passed (including parameterized width and height cases). The Xcode project file parses successfully and git diff --check is clean. No physical-device, fold-transition, keyboard, or accessibility UI result is claimed by these checks.

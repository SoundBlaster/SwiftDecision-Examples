# City Chain roadmap

Updated: 2026-09-27.

Product: a standalone, English-only U.S. city-chain game for children. Show full state names, postal abbreviations, and state-capital markers.

## Scout, our traveling companion

Status: first sprite integration implemented after approval; on-device polish remains pending.

Current work: [Scout character direction](DESIGN/SCOUT_CHARACTER.md), a dedicated expression sheet and the [first transparent sprite set](DESIGN/ScoutSprites/README.md). Scout now appears in the City Chain header and feedback card, with poses driven by turn outcomes. Xcode Tools MCP build passed for iPhone Air Simulator; device readability, edge polish and animation review remain pending.

Scout is a friendly raccoon who collects cities in a road-trip atlas. The existing City Scout opponent becomes a recognizable companion who encourages exploration and helps after mistakes.

### Art direction

- Rounded silhouette, large head, small body, expressive ears, striped tail.
- Blue-gray fur and a light muzzle; amber backpack and a green neckerchief, matching the app palette.
- A folding paper map is Scout's signature prop. It occasionally unfolds too far, becoming a gentle visual joke.
- Keep facial expressions readable at avatar size. Avoid text baked into artwork.
- Warm, curious and supportive; never disappointed in or mocking a child.

### Reactions

| Moment | Scout's response |
| --- | --- |
| Welcome | Waves a paw: “Where shall we go?” |
| Thinking | Studies the map and shifts their gaze |
| Accepted city | Nods and stamps the atlas |
| State capital | Presents a small star |
| Invalid or repeated city | Tilts their head and offers a helpful hint |
| Finished round | Raises a small flag |

### Delivery phases

1. **Concept approval:** compare silhouettes, colors and expressions; select one character sheet.
2. **Small first version:** welcome, thinking, celebration and try-another poses; a compact avatar for feedback and a larger companion beside the game heading.
3. **Production artwork:** separate transparent PNG sprites in Asset Catalog with consistent canvas dimensions, scale and anchors. Prepare independent body-part layers later if articulation is needed.
4. **SwiftUI integration, after approval:** `ScoutPresentation` supplies pose and reaction identity to `ScoutView`. Use `Image`, opacity transitions, event-triggered `KeyframeAnimator` reactions and a gentle `phaseAnimator` idle; honor Reduce Motion and VoiceOver. See the [API and delivery plan](DESIGN/SCOUT_CHARACTER.md#planned-swiftui-implementation).
5. **Polish:** capital celebration, supportive hints, atlas stamps and opening/closing display transitions.

Acceptance criteria: Scout never obscures controls or city names, never delays a turn, remains recognizable at small sizes, and communicates the same state without animation. Decorative artwork is hidden from VoiceOver; any important message remains ordinary accessible text.

## City atlas: help is always available

Status: searchable catalog, offline map data and adaptive Pocket Atlas prototype implemented; on-device validation remains pending.

- [x] Keep **Atlas** in the leading navigation toolbar, available throughout the game without reserving a bottom bar.
- [x] List the existing curated catalog: 150 cities, including all 50 state capitals.
- [x] Search city names by prefix, ignoring case and diacritics; state names and abbreviations remain visible as city details.
- [x] Put unused cities matching the current starting letter first; identify visited cities and other starting letters.
- [x] Selecting a ready city copies its name into the field without submitting it.
- [x] Allow browsing during Scout's turn and after a finished round.
- [ ] Verify the complete search → choose → send flow on the owner's iPhone Air.
- [x] Add the offline map using verified Census 2024 state boundaries and representative points; preserve the searchable list as an accessible alternative.
- [x] Keep the atlas alongside gameplay when available geometry fits both panes; use the same game session in compact and expanded layouts.

Earlier native previews (before moving Atlas to the toolbar): [fixed atlas entry](DESIGN/Images/city-atlas-entry-preview.png), [catalog while loading](DESIGN/Images/city-atlas-list-preview.png). Preview rendered on Duo; it does not verify selection or keyboard interactions.

The atlas is a learning aid, not a penalty or a limited hint currency. The catalog is a curated starting point, not an exhaustive list of U.S. cities.

## Adaptive exploration on iPhone Duo

Status: Pocket Atlas is approved and implemented as an adaptive prototype. The first SpecificationCore layout policy and Duo book/notebook adaptation are implemented; runtime validation remains pending.

Use the compact outer display for a focused turn-by-turn game. Use additional space on the unfolded inner display for useful companion content: a U.S. atlas, the current city's state information, or the trip collection. Both sizes share the same game, input draft and selected city.

- [x] Review current Apple guidance, installed SwiftUI skills and local Simulator evidence (2026-09-27; includes freshly exported Xcode 27.1 App Resizability).
- [x] Prepare graphic concepts for outer, inner and tabletop presentations, including keyboard behavior.
- [x] Compare the prepared concepts with the product owner (positive visual feedback; safe-area details need refinement).
- [x] Approve Pocket Atlas as the primary composition; keep the same focused game and composer in compact layouts.
- [x] Prototype a persistent expanded atlas and game pane using available geometry and one game session.
- [ ] Verify display transitions, safe areas, rotations, Dynamic Type, keyboard focus and Reduce Motion on device.

The implementation contract for iPad, Duo book fold, and Duo notebook/tabletop layouts is in the [adaptive layout specification](CITY_CHAIN_ADAPTIVE_LAYOUT_SPEC.md). Research, constraints and concept images are recorded in [the Duo concept proposal](DESIGN/CITY_CHAIN_DUO_CONCEPTS.md).

## Design boundaries

- Additional space should improve the child's understanding, rather than add a dense dashboard.
- The keyboard must not cover the active question, submission control or essential feedback.
- Prefer documented arrangement and reserved-region APIs for layout. Apple documents hinge interaction separately; reserve that for optional effects, not the game's core controls.
- Treat collectible passports and extra city facts as proposed features with their own data requirements.
- Game rules and learning content must remain available on ordinary iPhones.

## Route-first screen layout

Updated after on-device UX review, 2026-09-27.

- Reserve the bottom inset for the composer and, only when needed, a compact input error.
- Show successful turn feedback in the main scrollable content before the route. It does not cover the route.
- Both message placements have a 44-point close target, a horizontal swipe-to-dismiss action and a VoiceOver dismissal action. Messages do not expire on a timer.
- Keep the searchable atlas in the navigation toolbar. Starter suggestions appear before the first move; expanded gameplay also shows available cities without submitting them.
- Keep the large blue invitation and hero only before the first accepted city. During play and at round end, use a compact Scout/status/starting-letter row in the game pane. The expanded atlas stays visible beside the game with a short route preview and full-history access; compact layouts retain the full route list. A new round restores the starter composition.
- When the city field gains focus, scroll to the route end; repeat after the keyboard finishes appearing to use the final viewport. Skip the empty trip and atlas search, respect Reduce Motion, and leave manual scrolling available.
- [ ] Review closing and swiping messages, keyboard errors, and automatic route scrolling on iPhone Air.

### Catalog and continuation update

- [x] Search city names by prefix, ignoring case and surrounding whitespace.
- [x] Expand the catalog to 150 cities; document the 50 additions in [catalog sources](CITY_CATALOG_SOURCES.md).
- [x] When a letter has no unused catalog cities, scan the previous letters of the last city, right to left, for both players.
- [x] Explain skipped letters in the turn prompt, route, and atlas. If every letter is exhausted, allow any new city.
- [x] Check prefix search and exhausted-letter transitions on device (confirmed by the product owner on 2026-09-27).

## Proposed: secondary travel-journal layer

Status: product idea for future exploration; not approved for implementation.

Use the variable space below the turn card as an optional, secondary celebration of the trip. It is frequently covered by the keyboard during the player's turn, so it must not contain hints, controls, required game information, or anything needed to submit a move. Hide or collapse it while the keyboard is visible without changing game functionality. Keep the existing open space part of the composition; avoid adding a full-width white dashboard card.

The leading concept is a small **Journey so far** journal: show the latest 2–4 cities as illustrated postcard, polaroid, or stamp-like stops connected by a dotted route, then a restrained summary such as `2 cities · 2 states · 1,040 mi`. A subtle landscape can tie it to the atlas art direction. Aim for roughly 180–250 pt of vertical space when available, adapting or omitting content on shorter screens.

Other optional journal treatments to explore independently (not all at once):

- **Trip progress:** cities visited, states collected, and current streak, with a small next-achievement teaser.
- **Postcard from the road:** one short fact about the latest city, with a city illustration when available.
- **State stamps:** a compact collection of states already visited, with remaining states shown as a quiet collection goal.

Keep these treatments subordinate to the current turn and route. Reuse the existing city catalog, route history, and fact data where possible. Before showing distance, define and document a deterministic distance calculation and its geographic source; omit the metric until that is settled. Prototype the journal options against the ordinary iPhone keyboard state and expanded iPad/Duo layouts before selecting one direction.

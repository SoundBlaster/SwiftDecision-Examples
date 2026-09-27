# Scout sprites — first asset set

Created: 2026-09-27, with built-in `image_gen`. These are raster pose assets for the planned SwiftUI integration; no app source has been changed or device build performed for this asset-only step.

Open [the interactive asset preview](preview.html) to switch poses, compare light/dark/blue backgrounds and inspect the avatar at small CSS sizes.

| File | Intended state |
| --- | --- |
| [scout-welcome.png](scout-welcome.png) | Welcome / neutral friendly companion |
| [scout-thinking.png](scout-thinking.png) | Looking at the map while a turn is processed |
| [scout-celebration.png](scout-celebration.png) | Grounded joyful pose; SwiftUI can animate the bounce |
| [scout-try-another.png](scout-try-another.png) | Encouraging another attempt |
| [scout-avatar.png](scout-avatar.png) | Compact head-only companion |

## Export and integration notes

- PNG RGBA with real alpha; no labels or background plates are baked in.
- Four full-body sprites use the same 1254 × 1254 canvas. Keep that canvas intact when importing into Asset Catalog: independent trimming would change registration.
- At alpha >= 128, the full-body bottom bounds range from y=1191 to y=1193 (exclusive); this is approximately a common 95% standing baseline, not proof of exact anatomical registration.
- Small head-position differences are intentional pose changes. The Thinking pose lowers and turns the head toward the map.
- A generated cutout can retain faint low-alpha edge pixels. Review final blending on the actual UI backgrounds and actual display sizes before release. Pixel-perfect normalization and device animation review remain pending.
- The avatar intentionally uses just the head for small-size readability; the earlier bust variant was not selected because its curved lower edge retained a light fringe.
- These files are not a sprite atlas, skeletal rig, or layered vector artwork. Image transitions should be short; articulated movement requires separately prepared layers.

See [exact prompts](PROMPTS.md) and the [Scout implementation plan](../SCOUT_CHARACTER.md).

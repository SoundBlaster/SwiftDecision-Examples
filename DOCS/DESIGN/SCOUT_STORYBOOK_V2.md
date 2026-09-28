# Scout and the illustrated Pocket Atlas

## Art direction

Use the original Scout character sheet and Pocket Atlas concept as the visual references. Scout is a prominent companion with a transparent silhouette, teal neckerchief, yellow backpack and an open paper map. A warm comic speech bubble points toward his face. The map retains its local Census geometry and city coordinates while using softer green land, cream state boundaries, sparse terrain motifs and a blue dashed route.

The Duo side area is an adaptive placement opportunity: use measured trailing safe-area space below the system indicators, and keep the companion above the keyboard. The ordinary phone layout retains its composer-adjacent placement.

## Acceptance evidence

- The existing Xcode workspace built and launched CityChainApp on the iPhone Duo simulator.
- [Duo inner display at first stop](Images/city-chain-storybook-duo-inner.png): the seated Scout fits inside the trailing screen edge beside the composer; the map uses the illustrated palette.
- The Austin–Nashville map preview rendered successfully.
- Interactive keyboard, message-dismissal and map-opening checks remain unverified: the Xcode interaction session could not be recovered and Device Hub accessibility capture timed out.

## New sprite

- Asset: `CityChainApp/Resources/Scout.xcassets/ScoutCompanion.imageset/scout-companion.png`
- Reference: `DOCS/DESIGN/Images/scout-character-sheet-v1.png`
- Generator: built-in `image_gen`, with `transparent_background: true`.
- Output: 1254 × 1254 PNG with an alpha channel; copied into the asset catalog without changing the original reaction sprites.

### Generation prompt

Use case: illustration-story. Create ONE production game sprite with genuine transparent background, based on the provided Scout character sheet as identity/style reference. Preserve this exact cute raccoon character: oversized lively dark eyes with catchlights, fluffy slate blue-gray fur, cream eye brows and muzzle, striped bushy tail, teal neckerchief and small mustard yellow hiking backpack. Scout is seated comfortably, full body and tail visible, holding an open folded pastel paper map on his lap, looking up toward the upper LEFT with a warm delighted curious smile as if speaking to a child. Soft painterly children's picture-book gouache finish, simple tactile fur shading, clean generous silhouette, slightly three-quarter view. This sprite will sit in the bottom RIGHT corner of a mobile game next to a speech balloon so direct his attention toward upper left. Large head, little rounded feet, very expressive friendly face. Fill about 90 percent of a square frame with small transparent safety margins. No landscape, floor, background panel, white rectangle, border, text, speech balloon, icons, watermark, or drop shadow. Render only the single isolated seated raccoon with his map. Match original character design closely, not a realistic animal or glossy toy.

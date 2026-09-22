# OracleBallApp rendering

OracleBallApp is an iOS 26, Swift 6 demonstration target. It presents a local,
deterministic Magic 8 Ball surface and keeps the rendering layer independent of
the eventual SwiftDecision provider.

## Running the demo

The target is declared in `project.yml` as `OracleBallApp`, with an iOS 26.0
deployment target and the `OraclePresentation` package product. Generate or
open the Xcode project that contains this target, select the **OracleBallApp**
scheme, choose an iOS 26 simulator, and run. The app registers
`OracleRevealComponent`, `OracleMotionComponent`, and `OracleRevealSystem` at launch.

The shader requires the optional Metal Toolchain component. If Xcode reports
that `metal` cannot run, install it with `xcodebuild -downloadComponent MetalToolchain`.
The CI workflow installs this component before compiling the applications.

The current viewport uses a deterministic sample answer. `OracleBallViewport`
starts a short local delay and calls `OracleScene.present`; this is presentation
demo plumbing, not an inference request. A future SwiftDecision integration can
call the same `beginWaiting(request:)` and `present(answer:request:)` boundary
when its decision result is available.

## File boundaries

| Path | Responsibility |
| --- | --- |
| `OracleBallApp/app/entrypoint` | System registration and app entry point |
| `OracleBallApp/pages/oracle/ui` | Screen composition and cosmic backdrop |
| `OracleBallApp/features/ask-oracle/ui` | Question field and sample mode selector |
| `OracleBallApp/entities/oracle-ball/model` | Reveal and motion components |
| `OracleBallApp/entities/oracle-ball/lib/motion` | Core Motion lifecycle and neutral attitude |
| `OracleBallApp/entities/oracle-ball/lib/geometry` | Procedural mesh generation |
| `OracleBallApp/entities/oracle-ball/lib/rendering` | Scene, light, texture, materials and Metal shader |
| `OracleBallApp/entities/oracle-ball/ui` | Stable RealityView viewport |
| `OracleBallApp/shared/assets` | Bundled generated nebula |
| `Sources/OraclePresentation` | Pure reveal and parallax math, tested without a renderer |

## Scene ownership

`OracleScene` builds the RealityKit hierarchy:

- a perspective camera at positive Z;
- a procedural unit sphere with a positive-Z circular opening of radius `0.52`;
- procedural torus meshes for the metallic rim and inner ring;
- a dark cavity wall, a soft circular aperture shadow, and a thin transparent window disk;
- the floating answer plate, its textured front, and separate perimeter/back geometry;
- a deterministic image-based-light environment and key/rim lights.

`OracleRevealSystem` is the sole owner of the plate transform and the custom
material absorption controls. The `OracleRevealComponent` state machine moves
through `submerging`, `stirring`, `revealing`, and `holding`. The system swaps
the staged incoming face only after the old face has submerged, then samples
the pure `TriangleReveal` presentation math from the `OraclePresentation`
package.

The SwiftUI viewport passes `scenePhase` into the scene. Rendering time pauses
when the scene is not active. The environment also passes
`accessibilityReduceMotion`, which keeps the plate at the window, animates only clarity/absorption,
and removes plate rotation, camera parallax, and lighting drift. The reveal task uses an identity containing the request ID and renderer
presence so a newer request cancels the previous staged demo result.

## Motion and depth cues

`OracleMotionInput` reads fused Core Motion device attitude at 60 Hz, using the
first sample as neutral. A new neutral pose is captured after resuming motion
or changing portrait/landscape orientation. The renderer polls the latest sample;
sensor updates do not trigger SwiftUI view updates.

`OracleParallax` computes a relative quaternion, bounds each tilt axis to
±0.35 radians, and smooths it with a 0.18-second exponential response. The
render system then moves the perspective camera, rotates the studio image light
and key/rim rig, and adds a small tilt to the floating plate. The silhouette ring
tracks the camera so it stays tangent to the sphere. Lighting also drifts slowly
at rest, including on simulators without motion sensors.

Plate bob and roll are 1.8× the initial prototype amplitudes (`0.0108` units and
`0.027` radians). Gentle pitch and yaw make its thickness and depth visible.
Reduce Motion disables all of these movements and stops sensor updates; the
viewport also stops sensors while inactive or offscreen.

## Geometry and materials

`OracleMesh` contains no third-party geometry dependency:

- `shell()` samples a high-resolution sphere from the opening rim over the back
  hemisphere, with outward normals and a real open boundary;
- `ring(radius:tube:)` creates a torus in the XY plane;
- `triangle()` provides the front face and upright UVs for the answer texture;
- `triangleSides()` provides the back and perimeter prism with separate flat
  side normals and `0.035` thickness.

The front texture is rasterized once per answer by `OracleAnswerTexture`. The
`oracleFace` Metal shader blends a blurred and sharp texture according to the
sampled clarity and applies exponential artistic absorption. A subtle linear
base gradient spans the entire face. The shader modulates that gradient using
the plate's world-space normal and the viewing direction, so both floating and
phone tilt affect it. There is no localized bright band along the upper edge. `oracleEdge`
applies the same absorption controls to the plate edge. This is an artistic
approximation: there is no fluid simulation, true refraction, or bloom pass.
The transparent window, cavity wall, and layered plate positions provide the
depth and occlusion cues.

### Soft window shadow

`OracleWindow.metal` shades a separate circular mesh just under the glass.
Its radial opacity is zero through the central 42% of the radius, then increases
smoothly to 92% at the rim. The shadow is fixed to the window, so the plate moves
behind it with correct perspective and occlusion. Both the face and cavity are
shaded by the same layer. This is an aperture vignette; it does not blur the
answer or simulate optical bokeh. The parameters live in
`OracleMaterials.windowShadow()` and require no per-frame textures.

## Background asset provenance

`OracleNebula.png` is a checked-in 1024×1536 generated raster used by
`OracleCosmicBackground`. It is packaged as an Xcode asset and requires no
runtime network access. It was generated with OpenAI image generation on
2026-09-22 specifically for this demo. The brief called for a nearly black
portrait nebula, violet edge light, sparse stars, a cropped left moon and a dark
basalt ledge, with no text, UI or central ball. The supplied reference screenshots
were visual direction; they are not shipped as application assets.

## API references

- [RealityView](https://developer.apple.com/documentation/realitykit/realityview)
- [CustomMaterial](https://developer.apple.com/documentation/realitykit/custommaterial)
- [System](https://developer.apple.com/documentation/realitykit/system)

## Validation record

The iOS Simulator build and `swift test` (19 tests) passed with Xcode 27 / Swift 6.4.
FSD lint uses `.fsd-oracle.yml` and passes with the pinned FSD v0.4.0 tooling.
The tests cover monotonic approach, staying behind the glass, clarity, reduced
motion and negative elapsed time in addition to the existing City Chain suite.
On the iPhone 18 Pro / iOS 27 simulator, visual inspection confirmed the 3D
scene and legible face. Interaction checks covered Score (`87%`), Choice,
keyboard input, viewport resizing, portrait/landscape layout, keyboard dismissal
on submit, and background/foreground restoration.
The checked-in screenshot includes the motion and soft window shadow updates;
it is a simulator capture, not a design mockup. The shadow update passed both
simulator and signed device builds. Simulator inspection confirmed readable
answer text, smooth circular shading, and no opaque disk or glass-ordering artifact.
The motion update passes a signed iPhone Air build, device installation and launch,
and `swift test`
(25 tests: 16 City Chain, 3 reveal, 6 parallax). Parallax checks cover relative
attitude, limits, quaternion normalization, antipodal equivalence, smoothing,
and invalid inputs. Physical hand-tilt feel and rendering performance still
require a hands-on assessment; automated math checks do not establish those.

# Oracle: Apple Intelligence pilot

## Running

Open `CityChainApp.xcodeproj`, choose **OracleBallApp**, and run on iOS 26+.
Open **Oracle settings → Inference provider** and choose:

- **Jev**: existing online backend, requires an explicitly saved Keychain key.
  Existing 2.5-second shared budget, transient offline fallback and cooldown remain.
- **Apple Intelligence**: Foundation Models guided generation through SwiftDecision.
  No key or network provider. Requires eligible hardware, Apple Intelligence enabled,
  and its local model ready. Unsupported devices and Simulator display availability status.
- **None**: existing offline fixture answers, without AI inference.

The provider and normalization preference persist independently from the key.
First launch migrates to Jev when a saved key exists, otherwise None. Saving or
clearing a key never changes the selected provider. Switching providers cancels
an in-flight request and invalidates its completion ID. Empty questions and shakes
with empty input retain explicitly simulated random answers for all providers.

## Explicit alternatives

In Automatic mode, a valid extracted choice plan selects Choice locally through
SpecificationCore (`Explicit alternatives select Choice`). For `Hello or Kitty?`,
the backend receives one Choice request containing exactly `Hello` and `Kitty`;
there is no question-type classification. Explicitly selected Noul/Choice/Score
modes retain priority. Probability questions retain the existing classifier route,
and invalid/missing alternatives do not qualify for this shortcut.

The exact `Hello or Kitty?` regression was reproduced with an intentionally
misclassifying backend, then verified against the real local Apple model on the
Mac: accepted Choice in 2.26 s, with no classification stage.

This rule is provider-independent. The choice planner remains heuristic; output
policy can still abstain on an uncertain Choice distribution.

## Pilot contract

SwiftDecision is pinned to immutable revision `f962479c6251e9da224ef159181ae43a1f4cacbd`
from [PR #22](https://github.com/SoundBlaster/SwiftDecision/pull/22), enabling its
non-default `FoundationModels` SwiftPM trait. Other packages retain their versions.
Replace the pin with a release after the adapter is merged and released.

Oracle owns provider selection, Keychain storage, user-visible status and a shared
15-second inference budget across routing and answering. SwiftDecision owns the
Foundation Models schema, output decoding/validation, optional normalization and
decision policy. SwiftJev remains responsible only for Jev transport.

**Normalize Apple output** defaults on for this pilot (`sumToOne`); turning it off
uses strict output (`none`). Normalized mode requests relative weights in 0...1,
then divides by their positive sum. Strict mode requires probabilities summing to
1 within the adapter's tolerance. Normalization does not repair missing values,
wrong count, out-of-range values, or an all-zero distribution.

Apple estimates are self-reported and uncalibrated. This pilot checks integration
and format, not answer quality. Apple uncertainty can abstain; provider errors,
timeouts and invalid output do not silently become Jev or offline answers. Native
error descriptions are not shown because they can include request content.
History retains the model identifier and pipeline trace for accepted answers.
A request timeout bounds Oracle's wait; cancellation of actual model work remains
cooperative in the system framework.

## Validation

Default tests use injected guided-generation fixtures, never a live provider:

```sh
swift test --filter 'OracleInferencePreferencesTests|AppleIntelligenceOracleBackendTests|OracleProviderFallbackTests'
```

To explicitly run four synthetic questions through the real on-device Oracle
pipeline on an eligible Mac (Noul, Choice, Score, Automatic):

```sh
ORACLE_APPLE_INTELLIGENCE_SMOKE=1 swift test   --filter AppleIntelligenceOracleBackendTests.testLiveLocalOraclePilot
```

The smoke skips when the model is unavailable and accepts honest abstention.
It must never return a fallback. No Jev key is read by this smoke.
On this workstation, build artifacts and package caches must use the TB5 paths
required by repository guidance; commands above show only portable arguments.

## Local record (2026-10-24)

- Oracle iOS Simulator build and test build: passed with Xcode 27.1 / iOS 27.1 SDK.
- Full offline SwiftPM suite: passed (live smoke skipped by default).
- Real on-device-model inference through Oracle on the development Mac:

  | Mode | First run | Warm run | Warm outcome |
  | --- | --- | --- | --- |
  | Noul | 3.48 s | 2.73 s | accepted |
  | Choice | 0.83 s | 0.63 s | accepted |
  | Score | 1.23 s | 0.94 s | policy abstained |
  | Automatic | 1.97 s | 1.47 s | accepted as Noul |

  These are individual observations, not a benchmark. Score returned a valid
  distribution but did not clear the unchanged acceptance policy. No fallback
  was used. This does not establish correctness or calibrated confidence.
- iPhone Air Simulator automated UI regression: provider selection and persistence
  passed after narrowing the picker accessibility frame to its interactive control.
- iPhone Air Simulator manual UI: all provider options, Jev missing-key state,
  conditional normalization, Done, and Apple + normalization-off persistence
  passed. The Simulator reported the model available; unavailable-state UI and
  real physical iPhone inference still need checking.

## Revised local decision strategy

The subsequent [wording experiment](EXPERIMENTS/ORACLE_WORDING_2026-10-25.md)
measures bare OR, arbitrary-choice requests and semantic controls without changing
this strategy. It records the remaining zero-support failure as well as abstentions.
New experiments use English only: [instruction ablation](EXPERIMENTS/ORACLE_ENGLISH_INSTRUCTIONS_2026-10-25.md)
and [brief note before categorical selection](EXPERIMENTS/ORACLE_ESSAY_2026-10-25.md).

The pilot now explicitly selects SwiftDecision `.optionAssessment`:

- Choice/Score use one numeric field per option and a second generation with every
  option shifted to another position. Estimates are restored to the original order.
- Noul generates a supported/contradicted/unknown verdict plus a native scalar
  estimate, then repeats with a shifted categorical guide order.
- Score explicitly reports whether the context contains enough evidence.
- Disagreement, tied preference or missing evidence becomes a uniform distribution;
  the unchanged default policy abstains. Invalid fields remain errors.

The [original diagnostic](ORACLE_CHOICE_ORDER_DIAGNOSTIC.md) remains a baseline for
`.directDistribution`; its repeated 67/33 pattern is not a claim about the revised
strategy. The [SwiftDecision assessment report](https://github.com/SoundBlaster/SwiftDecision/blob/codex/foundation-models-backend/Documentation/Reports/FoundationModelsAssessment-2026-10-25.md) compares the two on 20 cases: the revised
strategy accepted 8 correct answers among 9 determinate tasks, skipped one Score,
and abstained on all 11 undecidable cases (including all eight user OR forms).
No wrong answer was accepted in that small run. Median observed latency was about
1.05 seconds instead of 0.63 seconds. These are not calibrated probabilities or a
production accuracy guarantee.

Apple abstentions now reveal “Not enough information” instead of leaving the old
answer visible. They are retained in question history with the full pipeline,
without an invented Boolean or confidence value. The stored mode is the requested
mode when no answer type was resolved. Other providers retain their current flow.

Automatic routing can require four native generations; the existing 15-second
shared budget covers the whole operation. A two-pass consistency check can still
agree on a wrong answer, and a single cyclic shift is not exhaustive order testing.

## Application-shaped prompt regression

The first revised adapter integration still abstained on `Choose the star: Hello or Sun`.
A bounded raw-assessment diagnostic showed `[1, 0]` in both alternative orders when
Oracle repeated the complete alternatives-bearing question as both task and context.
The consistency check caught this positional result, but lost answer coverage.

The existing colon-aware planner now also retains the criterion before the colon.
Choice passes that criterion as the task, alternatives separately, and an explicit
no-additional-observations context. Other question forms keep their original input;
no semantic criterion is invented for bare OR. This is application prompt assembly,
not an option-label heuristic in SwiftDecision, and applies consistently to providers.

After that change, real local inference through `OracleGameEngine` selected `Sun`
and `Goodbye` correctly in both original/reversed alternative orders (four cases).
`Hello or Kitty?` abstained with no classifier stage. Those two opt-in tests passed
in 6.69 seconds total on the Mac. The four-mode smoke completed without fallback:
Noul accepted, Choice/Score/Automatic conservatively abstained. Local inference is
still deliberately excluded from normal CI.

Final offline suite passed: 44 XCTest and 65 Swift Testing tests, with seven
opt-in local-model tests skipped. The final Oracle iOS Simulator build passed
on Xcode 27.1, with build outputs and caches on TB5.
Simulator UI verification confirmed that a bare-OR abstention replaces the previous
answer with `Not enough information`, persists in history, and opens a full 50/50
pipeline. No overlap/cropping was observed. A second check on the final build confirmed
`Sun` and `Goodbye` in the interface on the first submission of each criterion
question, with Apple + normalization ON. Physical iPhone inference with the revised
strategy remains unverified.

## Device follow-up

- Try all three providers, relaunch and verify selection.
- Disable normalization and try the same questions.
- Change providers while a local answer is being generated.
- Verify unsupported hardware / model downloading status and recovery.
- Compare cold and warm latency and inspect accepted answers' history traces.

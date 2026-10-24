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

SwiftDecision is pinned to immutable revision `886645e3c3ea97b08942c168f97b8ac2c1ecc8fa`
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

## Known Choice limitation

The [order diagnostic](ORACLE_CHOICE_ORDER_DIAGNOSTIC.md) reproduced the user's
first-option / 67:33 observation: all 12 normalized samples returned native weights
[1, 0.5], including semantic controls where the second option should win. Strict
mode returned 50:50 and abstained on four controls. The pilot's format integration
works, but the current numeric prompt/schema needs further evaluation before these
estimates can support meaningful choices. No automatic randomization was added.

## Device follow-up

- Try all three providers, relaunch and verify selection.
- Disable normalization and try the same questions.
- Change providers while a local answer is being generated.
- Verify unsupported hardware / model downloading status and recovery.
- Compare cold and warm latency and inspect accepted answers' history traces.

# Oracle GLiNER small pilot

This is a new pilot based on `main`; the archived Apple Intelligence experiment
remains on its closed PR branches. The dependency is the pinned implementation
from [SwiftDecision PR #23](https://github.com/SoundBlaster/SwiftDecision/pull/23).
It is not a released package update.

## Delivery and install

Oracle uses **Apple-Hosted Background Assets**, with the on-demand pack ID
`gliner-small-v1`. GLiNER is a free provider; a legacy
pilot preference no longer hides it. Nothing downloads on startup.

1. Build `OracleBallApp` in Xcode 27.1. Its local package enables the GLiNER trait.
2. In settings, tap **Install local model**. The app requests the Apple-hosted
   asset pack and shows progress/cancellation, then copies its content to staging.
3. Every runtime/license file is checked against the app's checked-in SHA-256
   inventory. Core ML validation and warm-up run before atomic activation.
4. The local provider becomes ready only after preparation. The app drops the
   downloaded Apple cache after activation; the owned model remains in private
   application support, excluded from backup. Core ML compilation and staging can
   temporarily require additional storage beyond the roughly 87 MB runtime.
5. **Remove local model** selects None when needed and removes this app's copy.

**Developer import** remains available for caller-provisioned compatible exports;
it preserves known license/provenance files when present. It does not silently
use GitHub as a fallback for a failed Apple download. The GitHub ZIP is an
independent distribution for library users.

## Build and publish the Apple asset pack

The portable model is published separately from Swift package releases:
[Core ML INT8 distribution](https://github.com/SoundBlaster/SwiftDecision/releases/tag/gliner2.5-small-coreml-int8-v1).
The ZIP includes all runtime files, Apache-2.0/MIT licenses and conversion notes.
Do not commit its weights into this repository or SwiftPM resources.

Use `Scripts/gliner/distribute.py` from SwiftDecision to create the licensed,
checksummed content and `AppleManifest.json`. From the output directory:

```sh
xcrun ba-package AppleManifest.json -o OracleGLiNER.aar
```

The generated manifest is on-demand, iOS only, and includes `GLiNERSmall/` under a
unique namespace. No unsupported Apple-hosted userInfo/language restriction is
added. Upload the `.aar` to Oracle's App Store Connect record, test through
TestFlight, then submit the pack for distribution with the app. An absent pack
is a visible installation error, never an inference fixture labeled as GLiNER.

Project configuration comes from `project.yml`: app `BAAppGroupID`,
`BAHasManagedAssetPacks`, `BAUsesAppleHosting`, and the embedded
`OracleModelDownloader` ExtensionKit extension using `StoreDownloaderExtension`.
App and extension share `group.ru.egormerkushev.oracle`. The new extension
requires an explicit bundle ID and a matching provisioning profile with that
App Group; the app's existing development profile cannot stand in for it.

For local download testing, follow Apple's [mock-server workflow](https://developer.apple.com/documentation/backgroundassets/testing-asset-packs-locally).
A successful unsigned build or `.aar` packaging does not prove delivery from
Apple servers or physical-device installation.

## Request behavior

- Loading includes one dummy local prediction to prepare Core ML before the
  provider becomes ready. The submit button shows preparation and stays disabled
  until this completes; typing remains available. Warm-up is not a question and
  is not written to history. No paid or network call is involved. The existing
  eight-second budget still applies to real questions after preparation.
- GLiNER errors stay visible. There is no implicit Jev or offline-answer fallback.
  Empty-question shake/widget random simulations remain explicitly simulated.
- A real inference failure is stored with its question, provider, safe failure
  category and available decision trace. The ball shows **Could not answer** for
  that request rather than restoring an empty plate after a clear. Failed
  history entries have no answer or confidence and can be exported for diagnosis.
  Cancellation/supersession keeps the existing request-ID guard.
- Only the local GLiNER pilot opts into `choiceOrdering: .canonical`. Its Choice
  schema is sorted by normalized option text and internal IDs are assigned after
  sorting; returned scores still follow the original user-visible order. The
  library default, Jev, Luna Decisio, Noul and Score remain unchanged. This is
  schema stabilization, not a quality or probability-calibration improvement;
  instructions and context, including any alternatives they contain, are not
  rewritten.
- `DecisionEngine` retains SpecificationCore validation, acceptance, tracing and
  abstention. A local abstention replaces the old visible answer with
  **Not enough information** and stores the diagnostic pipeline without an
  invented Boolean or confidence.
- Valid explicit alternatives route directly to Choice through the named
  SpecificationCore rule **Explicit alternatives select Choice**. They do not
  spend a second inference asking which question type was meant.
- A colon-separated criterion is preserved independently from the alternatives:
  `Choose the star: Hello or Sun?` sends `Choose the star` as instructions,
  `Hello`/`Sun` as options and `No additional observations.` as context. Bare
  alternatives keep their original question text.
- The checkpoint is English and has known confident errors in negation and
  missing-evidence cases. It scored 32/37 on the package's small labeled
  diagnostic set. Normalized scores are not calibrated probabilities.
- Parentheses and GLiNER structural markers in schema instructions/options are
  unsupported; errors are shown instead of silently rewriting the question.

## Validation

Ordinary CI does not need a model or API key:

```sh
swift test
swift test --traits GLiNER --triple arm64-apple-macosx14.0
```

Explicit local inference through the complete Oracle pipeline:

```sh
ORACLE_GLINER_CHECKPOINT=/path/to/gliner-small \
swift test --traits GLiNER --triple arm64-apple-macosx14.0 --filter OracleGLiNER
```

The fake-runtime tests cover opt-in preferences and migration, no implicit
fallback, one-request OR routing, criterion separation, atomic model activation,
retention of a previous valid installation, symlink rejection, cancellation and
removal. The opt-in test calls the real Core ML backend through OracleGameEngine
and verifies the model-backed Sun answer and SpecificationCore pipeline.

Local validation on 2026-10-25: default and GLiNER-enabled package suites passed;
the real import/activation/Oracle pipeline/removal test passed on the M4 Pro Mac,
and the signed iPhone app built with Xcode 27.1. The initial pilot was installed
and launched on the physical Air. The updated canonical-order version passed
the real-model Oracle pipeline and signed iPhone build but has not yet been
installed on the Air. Device latency, peak memory and UI verification remain
separate from these build and Mac runtime checks.

## Delivery validation, 2026-10-26

- Portable ZIP: 69,920,984 bytes; archive CRC and all ten manifest file hashes verified.
- Three deterministic packaging regressions passed (inventory/reproducibility, wrong model, symlink rejection).
- The pinned distribution imported through OracleGLiNERModelStore, compiled/loaded with Core ML, and answered a real Choice request through OracleGameEngine on Mac.
- Full package suites passed with optional traits disabled and with GLiNER enabled. Installer tests also cover failed/cancelled delivery, activation and cache cleanup ordering, and failed validation.
- The app/downloader extension code built for iPhone with signing disabled. Physical installation is not verified: the new extension needs an App Group provisioning profile, and authenticated Xcode provisioning failed with the currently stored API credential.
- The owner-created ASC app was verified (Apple ID `6827254640`). Apple accepted the manifest for asset pack `gliner-small-v1`, version 1. Archive upload was started; Apple processing and actual TestFlight download/cancel/retry and Air UI remain separate verification steps.

## App Store identity

The app record created by the owner is **Endless Answers: 8 Ball**, Apple ID
`6827254640`, bundle ID `ru.egormerkushev.oracle`, team `P8T2366K8X`.
The widgets and model downloader use the `.widgets` and `.model-downloader`
suffixes. The Home Screen display name is Endless Answers. A different bundle
ID installs alongside the earlier development app; private model/Keychain data
is not automatically transferred between their containers.

The shared App Group is `group.ru.egormerkushev.oracle`, as selected by the
owner. Every new explicit App ID must be associated with it before generating
provisioning profiles. Internal preference/history keys remain unchanged, but
changing the group does not migrate data from the former development App Group.
The asset pack identifier is `gliner-small-v1`: Apple rejects dots in asset pack
IDs, even though the local packaging tool accepts them. This restriction is
covered by the distribution packaging regression test.

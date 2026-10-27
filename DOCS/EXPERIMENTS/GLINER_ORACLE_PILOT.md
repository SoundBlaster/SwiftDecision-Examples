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

The runtime loaded and warmed up during validation is handed off once after
successful atomic activation. The next provider initialization reuses it and
logs `Reused runtime validated during installation`; it does not compile and warm
up the same model again. An invalid, cancelled or unactivated candidate is never
handed off. Removal and replacement invalidate the previous installation, and a
later cold start or provider change can still load the installed model normally.
Device latency improvements must be measured separately on an iPhone.

**Developer import** remains available for caller-provisioned compatible exports;
it preserves known license/provenance files when present. It does not silently
use GitHub as a fallback for a failed Apple download.

Debug builds from Xcode additionally expose **Developer import → Download from
GitHub**. This is an explicit alternative for local development, not an automatic
retry policy. Apple documents local asset-pack testing with a mock server and
device Development Overrides; a direct Xcode install is not a TestFlight delivery
test. TestFlight/App Store Release builds have neither the button nor the GitHub
download implementation (`#if DEBUG`).

The development downloader uses the separate library-user ZIP below. Its URL,
69,920,984-byte length, and SHA-256 are pinned in source. The archive hash is
verified before parsing; only regular files named by the checked-in inventory are
extracted, then every file is checked again before the existing Core ML validation
and atomic activation. Cancellation/failure leaves the active model unchanged.
The installation journal records the selected source. Questions are never sent to
GitHub. ZIP parsing uses [ZIPFoundation 0.9.20](https://github.com/weichsel/ZIPFoundation/tree/0.9.20),
licensed under MIT; model license/provenance files remain part of the inventory.

Opt-in live download check (through the public Swift source, not curl):
`ORACLE_GITHUB_DOWNLOAD_SMOKE=1 swift test --filter OracleGLiNERReleaseArchiveTests`.
This downloads about 70 MB and removes the temporary extracted model afterward.

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

## Internal TestFlight, 2026-10-27

Build 1.0 (2), ID `4369d33a-3d30-4a3d-97e4-ad06b542c44b`, passed Apple
processing. Export compliance was completed with usesNonExemptEncryption=false:
networking uses Apple's URLSession/HTTPS, credentials use Keychain, and the
model inventory uses CryptoKit SHA-256; no proprietary encryption was found in
the app or linked decision-provider sources. The same declaration is now in
Info.plist and project.yml for future builds.

The build's internal state is IN_BETA_TESTING and the internal tester is INVITED.
Internal has automatic all-build access. Explicitly adding the internal group
through the build's betaGroups relationship is rejected by Apple; it is not
needed for this group. Receipt of the invitation and real Apple-hosted model
delivery remain device checks. No external beta/App Store review was submitted.

## Missing-model fallback and haptics, build 1.0 (3)

When GLiNER is selected but not installed, submission now uses the existing
random Boolean simulation and shows “Random answer · without AI”. This is the
classic ball behavior, not semantic selection between extracted alternatives.
The original question is retained in history with simulated provenance and its
simulation trace. The GLiNER preference is preserved. A loading model remains
busy, and failures of an installed model retain their existing error handling.

OracleMissingModelFallbackSpec covers this policy, with tests for the complete
selection/installation/loading state matrix and simulated-answer provenance.
The tests passed without a downloaded model or provider credentials.

Drag feedback now begins on the first movement and repeats at 180 ms while
movement continues, with stronger transient intensity. The haptic engine is
created lazily in haptics-only mode; failed creation/playback can retry on the
next interaction, stopped/reset callbacks discard stale players, and playback
errors are logged by domain/code. UIKit impact feedback is used if Core Haptics
throws. Native compilation and actual tactile behavior are separate checks;
the latter still requires an iPhone.

Apple lifecycle reference:
https://developer.apple.com/documentation/corehaptics/preparing-your-app-to-play-haptics

## Managed-file access and installation diagnostics, build 1.0 (4)

The owner confirmed haptic feedback on the physical iPhone in TestFlight 1.0 (3).
Model installation still failed after an indeterminate spinner, with immediate
failure on retry. That UI alone does not prove download completion.

The old adapter resolved one file URL and treated its parent as a complete
checkpoint directory. The adapter now reads each pinned file through
AssetPackManager.contents(at:searchingInAssetPackWithID:) and materializes an
app-owned temporary tree on a separate actor. It does not enumerate or copy the
managed logical directory. The pinned SHA-256 inventory and the model store's
symlink/size checks remain enforced. Apple cache stays available on failure;
successful activation releases both the temporary copy and the Apple cache.

Safe installation failures identify manifest/download/files/validation/runtime
and NSError domain/code, without raw localized descriptions, URLs, paths, or
response bodies. Developer-import loader errors preserve their earlier contract.
The settings error includes those diagnostics so a physical failure can be
distinguished without guessing its phase.

Validation: 20 no-trait GLiNER tests passed (the opt-in native test was skipped).
Additional native smoke passed with the real pinned artifact and GLiNER enabled:
file materialization, exact inventory validation and native Core ML activation
on Mac. This smoke uses a file-reader fixture, not Apple's live delivery service.
Actual iPhone installation and the exact cause of the earlier TestFlight failure
remain unverified until the updated build is exercised.

ASC asset pack version 1 is READY_FOR_TESTING internally and
READY_FOR_BETA_SUBMISSION externally. The owner is recorded as an internal
tester with 1.0 (3) installed; external asset review is a separate requirement.
No external asset review was submitted by this change.

Apple file-access contract:
https://developer.apple.com/documentation/backgroundassets/assetpackmanager/url(for:)

## In-app installation log, build 1.0 (5)

Inference settings now expose a separate Model installation log sheet, available
before, during and after installation. It shows ordered timestamps, app/build,
manifest lookup, download progress (5% increments), managed-file reads with
relative names and byte counts, inventory verification, Core ML runtime/warm-up,
activation, cache cleanup and terminal success/cancellation/failure. Provider
reload readiness/failure is recorded separately after activation.

The sheet can follow new events, retry/cancel, clear, copy, and share an immutable
UTF-8 text snapshot named oracle-model-installation-log.txt. The last 300 events
persist locally between launches. No question text, credentials, absolute paths,
raw NSError descriptions or response bodies enter the typed journal.

The shared file materializer now serializes concurrent operations while awaiting
diagnostic callbacks, preserving cancellation and the store's no-suspension
replacement section. Diagnostics never change a successful activation into
failure if cache cleanup fails.

Journal tests cover event/timestamp/identity serialization, safe failure export,
bounded retention, throttled progress and file events before checksum failure.
The full no-trait GLiNER suite passed with opt-in native tests skipped; native UI,
sharing and persistent-log behavior still require device verification.

Build 1.0 (4) passed Apple processing and is IN_BETA_TESTING internally. This is
not proof that model installation is fixed on the iPhone. The owner clarified
that earlier attempts progressed smoothly to 100%, narrowing that failure to a
post-download operation. The journal is intended to identify the exact phase.

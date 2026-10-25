# Oracle GLiNER small pilot

This is a new pilot based on `main`; the archived Apple Intelligence experiment
remains on its closed PR branches. The dependency is the pinned implementation
from [SwiftDecision PR #23](https://github.com/SoundBlaster/SwiftDecision/pull/23).
It is not a released package update.

## Enable and install

1. Build `OracleBallApp` in Xcode 27.1. The local package reference enables the
   `GLiNER` SwiftPM trait, forwarded to SwiftDecision. The optional `OracleGLiNER`
   product is linked only by OracleBallApp, not the widgets or CityChain.
2. In Oracle settings, enable **Enable GLiNER pilot**. The persistent feature flag
   `com.soundblaster.oracleball.gliner-pilot` defaults to false.
3. Use **Import model folder** and select the complete GLiNER small INT8 export
   produced by `Scripts/gliner/prepare.py` in the SwiftDecision repository. The
   checkpoint revision and conversion procedure are documented in PR #23.
4. Importing validates and compiles the checkpoint before activation. On success,
   the selected provider becomes **GLiNER small**. The provider preference is
   independent from a saved Jev key. Saving a key does not switch away from GLiNER.
5. **Remove local model** releases the current game engine, selects None when
   needed, and removes only this app's installed checkpoint.

The app imports `gliner.json`, `tokenizer.json`, `tokenizer_config.json` and
`GLiNERSmall.mlpackage`. They live under the app's private
`Library/Application Support/OracleGLiNER/active` directory, excluded from backup.
About 87 MB is stored separately from the app bundle. The model and Python
export/runtime dependencies are never bundled as app resources. No model host,
automatic download, or shared credential is introduced by this pilot.

Import rejects symlinks, missing files and checkpoints over a 256 MiB storage
budget. Files are copied to staging and validated through the native backend.
Failed validation or cancellation leaves the previous installation intact.
Imported artifacts must retain Fastino's Apache-2.0 attribution when distributed.

## Request behavior

- GLiNER errors stay visible. There is no implicit Jev or offline-answer fallback.
  Empty-question shake/widget random simulations remain explicitly simulated.
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

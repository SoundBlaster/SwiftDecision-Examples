# English-only wording and instruction ablation — 2026-10-25

## Scope

Follow-up to the exploratory Russian wording run. All new user tasks, alternatives,
session instructions and schema descriptions are English. Historical Russian input
remains reproducible but is not used in these runs. Production behavior is unchanged.

The baseline uses the public Oracle engine, Automatic routing, the existing
`.optionAssessment` adapter and normalization, fresh greedy native sessions,
six-second shared question deadlines and the same bound/schema/policy as the pilot.
There is no hosted inference, provider key, retry or randomization.

Host: macOS 27.0 (26A428), Xcode 27.1 (27A9275). Apple Intelligence available on
the Mac, checkpoint version not exposed. SwiftDecision pin `f962479c6251e9da224ef159181ae43a1f4cacbd`;
production Oracle source `2d5560b11b72432b43b5976f0fbf2702b7b0a066`.

## English baseline

Colors (`red / blue`): six forms, both orders, three repeats = 36 questions.
`Hello / Kitty`: bare/any/first, both orders, two repeats = 12 questions.

| Prefix | Accepted | Abstained | Invalid output |
| --- | ---: | ---: | ---: |
| Bare `red or blue?` | 0 | 6 | 0 |
| `Choose any option:` | 0 | 6 | 0 |
| `Choose the first thing that comes to mind:` | 0 | 6 | 0 |
| `Which do you prefer:` | 0 | 6 | 0 |
| `You must choose exactly one option, even without a reason:` | 0 | 6 | 0 |
| `Choose the cool color:` | 0 | 6 | 0 |

All 12 Hello/Kitty questions also abstained. Main baseline: **48 abstentions,
zero accepted answers, zero errors**. Thus English alone does not restore arbitrary
selection. The old Russian cool-color zero-vector errors did not repeat in this
English matrix; language, lexical content and run timing changed together, so this
is not an isolated explanation of the old failure.

Six additional English controls (grounded cool-color facts, star and farewell,
each in both orders) selected the expected word in all six cases. These controls
are separate from the main 48-case comparison.

## Two-factor instruction ablation

Two original instructions explicitly encourage uncertainty/equal assessments:

Session:

> If no selection criterion is provided or the information is insufficient, indicate uncertainty.

Every numeric field description:

> Use equal positive support when no criterion is given.

Test the same 16 English arbitrary-choice samples in each profile: any/first ×
two word pairs × both orders × two repeats. The unchanged profile is the matching
subset of the English baseline; each changed profile adds 16 new decisions.

Only the exact indicated sentence is removed. For a schema ablation, the dynamic
schema is reconstructed with the same root/property names, field order, Double
types and range guides. Prompt text, greedy sampling, normalization, two-pass
alignment, timeout and acceptance policy are unchanged. Effective session
instructions and field descriptions are recorded per native pass.

| Profile | Accepted | Abstained | Invalid output |
| --- | ---: | ---: | ---: |
| Both original instructions present | 0/16 | 16/16 | 0/16 |
| Remove session uncertainty sentence only | 0/16 | 16/16 | 0/16 |
| Remove schema equal-support sentence only | 0/16 | 8/16 | 8/16 |
| Remove both sentences | 4/16 | 12/16 | 0/16 |

Raw behavior differs even when the final abstention looks the same:

- Unchanged: `[1, 1]` in every one of the 32 native passes.
- Session-only removal: all 16 color passes choose the first position `[1, 0]`;
  all 16 Hello/Kitty passes stay `[1, 1]`. The position winners disagree after mapping.
- Schema-only removal: eight decisions encounter a zero-support pass, correctly
  rejected by validation; the other eight still abstain.
- Both removed: all four `Choose any option: red or blue?` original/reversed/repeated
  cases select `red` consistently. The remaining twelve questions abstain.

This shows instruction sensitivity on this small fixed workload. It does not show
that either phrase is the sole cause, or that deleting them is a reliable fix.
The ablation profiles were run sequentially after baseline; this is not a
randomized repeated-run statistical study.

## Interpretation

The adapter asks for per-option support: 0 means contradicted, 1 fully supported.
When the task allows either word, equal support is a reasonable output for that
scoring question. Normalization then yields 50/50, and policy abstains. That scoring
contract is different from asking for one arbitrary selected ID. English wording
does not remove the distinction.

Do not infer that a short explanation or a categorical answer fixes calibration:
the [separate note-before-ID experiment](ORACLE_ESSAY_2026-10-25.md) measures a
different output contract, without fabricating a probability vector from the ID.

## Artifacts and reproduction

[Raw rows](ORACLE_ENGLISH_INSTRUCTIONS_2026-10-25.jsonl): 102 decisions and 200 native
generations across English baseline/controls and the three changed profiles.
Measured question time totals 109.056 seconds, median 1.022 seconds; not a physical
iPhone or energy benchmark. Diagnostic completion does not imply semantic or
format success; all eight invalid predictions are retained.

```sh
# English baseline and controls, batches 0..8
ORACLE_WORDING_DIAGNOSTIC=1 ORACLE_WORDING_BATCH=0 \
swift test --filter OracleWordingDiagnosticTests

# Changed instruction profiles, batches 0..7
ORACLE_WORDING_DIAGNOSTIC=1 ORACLE_WORDING_PHASE=ablation ORACLE_WORDING_BATCH=0 \
swift test --filter OracleWordingDiagnosticTests
```

Use repository-required TB5 paths on this workstation. Normal tests skip native
inference and validate matrix construction. No production code or CI inference changes.

# Oracle wording experiment — 2026-10-25

## Question and scope

Can wording alone make the current Apple Intelligence Oracle choose an arbitrary
alternative instead of abstaining? This experiment changes only fixed test inputs.
Production prompts, schema, strategy, routing, policy, normalization and sampling
remain unchanged. No spontaneous-choice feature is implemented here.

## Method

- Public `OracleGameEngine.answerWithTrace`, Automatic mode, Apple backend,
  `.optionAssessment`, normalization enabled, no fallback or hosted inference.
- Injected observational client uses the same fresh native sessions, request
  instructions/schema and greedy generation as production. It records both native
  numeric assessments without modifying input or output.
- Record the application-assembled task/context/options, native pass inputs/weights,
  final probabilities/outcome and elapsed time. Every question routed directly to
  Choice with the expected two options; no classifier stage appeared.
- macOS 27.0 (26A428), Xcode 27.1 (27A9275), Apple Intelligence available locally on
  the Mac. Adapter implementation pin `f962479c6251e9da224ef159181ae43a1f4cacbd`;
  production application source revision `2d5560b11b72432b43b5976f0fbf2702b7b0a066`.
  Apple exposes no stable model checkpoint ID here. This is not a physical-iPhone run.
- Six cases per batch, six-second shared per-question deadline, 40-second batch
  admission bound. Fresh sessions for both passes. All nine batches completed.

## Predefined main matrix: 48 questions

Colors: six forms × two alternative orders × three repeats = 36 decisions.
`Hello / Kitty`: the first three forms × two orders × two repeats = 12 decisions.
The first order alternates across forms/repeats; both orders are always measured.

All color questions end in `красный или синий?` or its reversal.

| Form | Prefix before the alternatives | Accepted | Abstained | Error |
| --- | --- | ---: | ---: | ---: |
| Bare | none | 0/6 | 6/6 | 0/6 |
| Any | Выбери любой вариант: | 0/6 | 6/6 | 0/6 |
| First to mind | Выбери первое, что придёт на ум: | 0/6 | 6/6 | 0/6 |
| Preference | Что тебе больше нравится: | 0/6 | 6/6 | 0/6 |
| Forced | Обязательно выбери ровно один вариант, даже без оснований: | 0/6 | 6/6 | 0/6 |
| Criterion | Выбери холодный цвет: | 0/6 | 0/6 | 6/6 |

For `Hello / Kitty`, bare, any and first-to-mind each abstained on all four questions.
Overall main matrix: **0 accepted, 42 abstained, 6 errors**.

The six color criterion errors contain a native `[0, 0]` pass. Normalization correctly
rejects zero total weight before order consistency or acceptance. Three original-order
cases first generated `[0, 1]`, then `[0, 0]` after swapping; the three reversed-order
cases generated `[0, 0]` immediately. These are invalid predictions, not abstentions.
The diagnostic reports errors separately; a completed diagnostic test is not a
claim that all model responses were valid.

### Before the consistency check

Across both word pairs, **all 40 native passes** for the any/first-to-mind forms
returned `[1, 1]`. Each normalized pass is already 50/50. Thus removing only the
order-consistency check cannot make those samples produce a unique preference.

The bare/preference/forced forms also produced positional `[1, 0]` templates in
some passes, or equal support. Their final result was always uninformative. For
example, a first-position winner in both shifted passes refers to different words;
that is exactly the positional pattern the consistency check is intended to catch.

The main experiment deliberately measures the current application input assembly:
colon forms split the task from alternatives and use the no-additional-observations
context, while bare questions retain the full question as task/context. Those are
different rendered inputs, recorded in the raw rows. This is a practical comparison,
not an isolated causal test of individual words with identical prompt structure.

## Additional diagnostic controls: six questions

These were added after observing the color criterion errors. They are separate
from the predefined 48-case matrix and have only one trial per alternative order.

| Control | Result in both orders |
| --- | --- |
| Синий — холодный цвет, красный — тёплый. Выбери холодный цвет: красный или синий? | синий, 2/2 accepted |
| Blue is a cool color and red is a warm color. Choose the cool color: red or blue? | blue, 2/2 accepted |
| Choose the star: Hello or Sun? | Sun, 2/2 accepted |

Both native passes in each control agreed on the correct semantic alternative
after index restoration, yielding a one-sided distribution. These are generated
estimates, not evidence of calibrated 100% confidence.

Across all 54 decisions there were 105 native generations (three invalid first
passes stopped before the second). Sum of measured question times: 63.426 seconds;
overall median: 1.054 seconds. These include warm/cold effects and are not a device
performance benchmark. No hosted requests or credentials were used.

## Conclusions

1. The tested arbitrary-choice wording did **not** overcome the current adapter's
   equal-support/uncertainty behavior on either word pair.
2. The raw output disproves the narrower hypothesis that only the two-pass check
   prevents any/first-to-mind choices: those passes were already equal individually.
3. A bare criterion is not universally sufficient: the Russian cool-color control
   produced malformed zero-support output, while added factual grounding succeeded.
4. Fixed backend uncertainty instructions and schema descriptions are a plausible
   influence, not a proven sole cause. Isolating that requires a separate prompt
   ablation with the same tasks and recorded native outputs.
5. There is no evidence here for random or unbiased spontaneous choice. Greedy
   repeated answers, successful semantic controls and distribution shape do not
   establish randomness, calibration or general reliability.

Next bounded experiment: compare the unchanged adapter instructions with a neutral
arbitrary-selection instruction in the diagnostic harness, holding schema, options,
order and sampling fixed. Keep this separate from production routing changes.

## Reproduction and artifacts

[Raw rows](ORACLE_WORDING_2026-10-25.jsonl) contain only the fixed synthetic questions.
The opt-in test is `OracleWordingDiagnosticTests.measureSixApplicationQuestions`.
Normal tests run only the offline matrix check; live inference is disabled by default.

```sh
ORACLE_WORDING_DIAGNOSTIC=1 ORACLE_WORDING_BATCH=0 \
swift test --filter OracleWordingDiagnosticTests
```

Run batches 0–7 for the main matrix, 8 for the additional controls. On this
workstation, also use the TB5 scratch/cache options required by repository guidance.
No CI inference or CI monitoring is needed for the experiment.

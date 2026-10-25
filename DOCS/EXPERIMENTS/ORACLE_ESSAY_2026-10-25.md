# Brief note before selection — 2026-10-25

## Hypothesis

Would generating a short user-facing comparison before selecting an alternative
improve behavior enough to justify extra time? All model instructions and test
inputs are English. This is a separate categorical-output experiment, not a
production adapter change or a probability-backend quality comparison.

## Protocol

Same eligible Mac and SDK as the [English instruction ablation](ORACLE_ENGLISH_INSTRUCTIONS_2026-10-25.md):
macOS 27.0 (26A428), Xcode 27.1 (27A9275), native SystemLanguageModel.default.

Sixteen fixed questions per variant, each in both alternative orders:

- Eight explicit arbitrary requests: any/first-to-mind × colors/Hello-Kitty × orders.
- Four semantic controls: star and grounded cool-color task × orders.
- Two missing-personal-fact questions: birth city, London/Paris × orders.
- Two bare Hello/Kitty questions without an explicit arbitrary-choice instruction.

Use Oracle's existing planner to separate a colon-delimited task and options.
Fresh sessions, greedy sampling, maximumResponseTokens 256, twelve-second
cooperative deadline, four cases per batch. No retries, tools or hosted inference.
This screening has one trial per question/order, not repeated-run statistics.

The same session instructions in every variant explicitly permit an arbitrary
choice when requested, and require undetermined for missing factual information.
The selection field is a guided string with values `0`, `1`, `undetermined`.
An ID is not converted to a one-hot probability or passed through the production
DecisionEngine policy; ID output and accepted probability output are different contracts.

Variants:

1. **directID**: only the selection field.
2. **noteThenID**: a String field first asks for two or three user-facing sentences
   comparing alternatives, at most 60 words, using given facts or stated preferences.
3. **preferenceNoteThenID**: follow-up added after inspecting variant 2; changes only
   the note description to explicitly allow a subjective choice for arbitrary tasks
   while retaining factual uncertainty. It is post-hoc, not a predefined winner.

The raw rows contain complete fixed questions, rendered input, session instructions,
generated note/ID and latency. Each test records errors separately. All 48 generations
completed with a valid guided ID; no generation/guardrail/refusal errors were observed.
All generated notes were at most 34 words, below the requested soft 60-word limit.

## Results

| Metric | directID | noteThenID | preferenceNoteThenID |
| --- | ---: | ---: | ---: |
| Arbitrary requests returning an option | 8/8 | 4/8 | 8/8 |
| Arbitrary requests choosing the first position | 8/8 | 3/8 | 5/8 |
| Arbitrary paired forms selecting the same word in both orders | 0/4 | 1/4 | 1/4 |
| Correct semantic controls | 4/4 | 4/4 | 4/4 |
| Missing birth facts returning undetermined | 2/2 | 2/2 | 2/2 |
| Bare forms returning undetermined | 2/2 | 2/2 | 0/2 |
| Median observed latency | 0.453 s | 1.179 s | 1.138 s |

The paired arbitrary consistency metric requires the same actual word in both
orders; two undetermined results are not counted as a selected word. For arbitrary
tasks, changing words across orders is not itself a factual error. The metric only
helps detect the first-position shortcut and is not a universal acceptance rule.

Simple note-before-ID reduced arbitrary answer coverage: four requests acquired an
explanation of missing preferences and returned undetermined. The follow-up note
restored arbitrary answer coverage and reduced, but did not eliminate, position
sensitivity. It also broadened selection to bare questions, showing that the
instruction changed behavior beyond explicitly arbitrary tasks.

Explanations are not proof of faithful reasoning. One follow-up note called both
Hello and Kitty greetings, which is incorrect. Some claimed a random choice despite
greedy decoding and no controlled RNG. These statements do not establish randomness
or explain the actual causal process behind the selected ID.

Total measured question time was 48.860 seconds. The cold first directID request
took 2.111 seconds; medians do not erase cold-start costs. Measurements are local
screening observations, not physical-iPhone latency or calibrated decision quality.

## Guardrails versus ordinary model behavior

Apple documents safety checks on model input/output, model refusals, and refusal
text. A normal response such as “I don't have a preference for colors” does not
identify whether a filter, model alignment or an application's own instructions
caused it. Our no-error categorical runs, including eight arbitrary selections in
the follow-up, provide no evidence of an absolute ban on choosing colors.
See [Improving the safety of generative model output](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output).

Apple also documents placing a reasoning field before an answer field; it warns
that an on-device model may still answer unreliably. This motivates an experiment,
not a correctness guarantee. Our field contains a brief user-facing comparison,
not a claim to expose the model's internal reasoning.
See [Prompting an on-device foundation model](https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model).

## Conclusion and next step

Brief text before selection is worth further testing, but a note alone did not
fix arbitrary selection here. Explicit task semantics mattered more than merely
adding text, and neither variant established unbiased/random choice or confidence.

Next compare the same follow-up instruction in **ID-only** and **note-before-ID**
schemas over a larger frozen set, with repeated/permuted runs. This will help
separate the benefit of the extra instruction from the benefit of generating text.
Do not introduce a production strategy on the basis of this small screen.

## Artifacts and reproduction

[Raw rows](ORACLE_ESSAY_2026-10-25.jsonl), fixed synthetic inputs only.

```sh
ORACLE_ESSAY_DIAGNOSTIC=1 ORACLE_ESSAY_BATCH=0 \
swift test --filter OracleEssayDiagnosticTests
```

Batches 0–3 directID, 4–7 noteThenID, 8–11 the post-hoc preferenceNoteThenID.
Apply repository-required TB5 scratch/cache paths on this workstation. Default
tests check the English, balanced corpus and skip all native inference. Production
code and app installation remain unchanged.

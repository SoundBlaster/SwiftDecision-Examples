# Matched instructions: ID versus note order — 2026-10-25

The [required 30–60-word follow-up](ORACLE_LONG_ESSAY_2026-10-25.md) generated longer
comparisons and treats short text as protocol failure. It found no selection benefit.

## Question

Does generating text before a selected ID help independently of the extra
arbitrary-choice instruction used in the earlier exploratory note experiment?
All model-facing text is English. Production behavior remains unchanged.

## Frozen protocol

- 24 fixed English questions, both alternative orders included: 12 explicit
  arbitrary requests, six semantic controls, four missing-fact questions and two
  bare Hello/Kitty forms. Each query has two repeats per strategy.
- Three strategies: **directID**, **noteBeforeID**, **noteAfterID**. Total 144 native
  generations. The same question/repeat is evaluated in all three strategies.
- Same rendered task, context, alternatives, session instructions, root schema name,
  selected-ID property description/guides, fresh sessions, greedy sampling and
  256-token maximum. The only schema differences are the presence and order of a
  neutral String note field. Its description is identical in both note strategies.
- The complete shared instruction permits arbitrary selection only for explicitly
  arbitrary tasks, requires undetermined for unsupported facts, asks for two or
  three sentences up to 60 words if a note is present, and prohibits invented
  randomness/personal-experience claims.
- Counterbalanced deterministic rotation of strategy order across samples/repeats;
  six cases per batch, 40-second admission budget, 12-second cooperative deadline
  per generation. Strategy order is not randomized. Each pass is a fresh session.
- macOS 27.0 (26A428), Xcode 27.1 (27A9275), native SystemLanguageModel.default,
  available on this Mac. Apple does not expose a stable checkpoint ID. No hosted
  calls, keys, tools, retries, production fallback or physical-iPhone inference.
- Corpus/harness source was fixed before the native runs. SHA-256 of
  `OracleMatchedEssayDiagnosticTests.swift`:
  `5fc2687e221a347dda463c6135b4d63c02aaadb81950ec8d4d32e7f3562cef2f`.

The observer verifies exact equality of effective instructions across all rows and
of rendered input/options across each matched triple. The model sees the whole
schema before generating, so even an answer-first schema can influence its answer;
field order does not prove exposure of the model's actual internal reasoning.

## Results

Each strategy has 48 generations. All outputs have a valid guided ID; there are
no generation errors. ID output is not converted to a probability distribution or
treated as an accepted SwiftDecision prediction.

| Metric | directID | noteBeforeID | noteAfterID |
| --- | ---: | ---: | ---: |
| Arbitrary requests selecting an option | 24/24 | 24/24 | 24/24 |
| Arbitrary requests choosing the first position | 24/24 | 18/24 | 24/24 |
| Paired arbitrary forms choosing the same word in both orders | 0/12 | 6/12 | 0/12 |
| Correct semantic controls | 12/12 | 12/12 | 12/12 |
| Missing-fact questions correctly returning undetermined | 4/8 | 0/8 | 0/8 |
| Unsupported selections on missing-fact questions | 4/8 | 8/8 | 8/8 |
| Bare forms returning undetermined | 0/4 | 0/4 | 0/4 |
| Median observed latency | 0.459 s | 0.692 s | 0.731 s |
| Maximum observed latency | 2.350 s | 1.400 s | 4.407 s |
| Same selected ID/word across the two repeats | 24/24 | 24/24 | 24/24 |

Choosing a different arbitrary word after changing option order is not a factual
error; the paired metric only characterizes position sensitivity. Likewise, a
stable word is not evidence of calibrated confidence or randomness. The first
directID call was cold and took 2.350 seconds; latency is screening evidence only.

## Concrete failures

For `Which city was I born in: London or Paris?`, directID returned undetermined
in both orders and both repeats. Both note variants chose the first city instead,
even though the shared instruction explicitly requires missing facts to remain
undetermined. One note-before response said:

> The selection is arbitrary as the birth city is unknown.

That is an unsupported answer rationalized as an arbitrary choice, not evidence
of a birthplace. The note-after variant showed the same regression.

For the next coin toss, all three strategies chose heads without observations.
That is an unsupported forecast; we do not label it factually false because the
future outcome is not known. It still violates this experiment's missing-evidence
requirement. Bare questions produced positional choices despite no explicit
arbitrary-request prefix; this is another boundary to test before product use.

## Important limitation: no actual essay was generated

The requested note length was a soft instruction, not an enforced length guide.
The model did not follow it:

- noteBeforeID: 4–13 words, median 8.
- noteAfterID: 5–17 words, median 7.

Many notes were a single short sentence, for example “Selected an arbitrary option.”
This experiment therefore establishes behavior for a short text field before/after
an ID. It does **not** establish the benefit or failure of a genuine multi-sentence
essay. A further essay study must enforce or separately grade minimum text length,
without silently retrying short outputs or discarding their cost.

## Conclusion

With matched instructions, note-before-ID modestly reduced arbitrary position bias
but did not improve already-correct semantic controls, and both note variants
worsened missing-information behavior. The note-after control reinforces that
schema shape/order affects behavior beyond just extra instruction wording.

Do not enable this as a production strategy based on these results. There is no
general accuracy, calibrated-confidence, unbiased-sampling or physical-device
claim. Repeated outputs were identical on this small fixed greedy workload.

Next bounded experiment, if further essay evaluation is desired: require a real
30–60-word comparison, count short outputs as protocol failures, preserve matched
instructions/order controls, and retain the missing-fact regressions. Keep arbitrary
selection and evidence-based factual decisions as distinct evaluation categories.

## Artifacts and reproduction

[Raw rows](ORACLE_MATCHED_ESSAY_2026-10-25.jsonl) contain only fixed synthetic inputs,
effective instructions, schema property order, IDs, notes and timing.

Raw SHA-256: `eeb73d29877c6833e9919a54540a2e08eba12e7f12a286e6c4d2542280330870`.
Summed measured generation time: 100.877 seconds; process/build overhead is excluded.

```sh
ORACLE_MATCHED_ESSAY=1 ORACLE_MATCHED_ESSAY_BATCH=0 \
swift test --filter OracleMatchedEssayDiagnosticTests
```

Run batches 0–23 with repository-required TB5 scratch/cache paths on this workstation.
Default tests check the frozen English/balanced corpus and skip all live inference.
Full offline suite passed; no CI monitoring or app deployment was performed.

# Required 30–60-word comparison before ID — 2026-10-25

## Outcome

Longer generated comparisons did not improve selection on the fixed English
workload. They cost about 3.4 times the median inference latency, retained
first-position arbitrary choices, and did not improve missing-fact abstention.
Six of 48 essay responses failed the required minimum length and are explicitly
counted as protocol failures, not successful decisions.

## Protocol and supported constraints

The [previous 24-question corpus](ORACLE_MATCHED_ESSAY_2026-10-25.md) is unchanged:
12 explicit arbitrary-choice questions, six semantic controls, four missing-fact
questions and two bare alternatives, including both option orders. Each question
is evaluated twice per strategy in fresh sessions. Strategy order rotates across
samples/repeats. The main comparison has **96 native generations**:

- **directID**: one guided ID or undetermined.
- **instructedEssay**: a String comparison before the same ID, explicitly required
  to contain 30–60 whitespace-separated words. An independent validator rejects
  out-of-range text. Every raw ID is retained even when the protocol rejects it.

Both receive identical English session instructions and rendered task/context/
options. The shared instruction distinguishes arbitrary tasks from factual tasks,
requires undetermined for unsupported facts, and prohibits padding/randomness/
personal-experience claims. Sampling is greedy; maximumResponseTokens is 512 in
both strategies, with a 12-second cooperative deadline and no retries.

Native host: macOS 27.0 (26A428), Xcode 27.1 (27A9275), SystemLanguageModel.default
on the eligible Mac. No hosted inference, keys, provider fallback, device install
or probability vector fabricated from the selected ID. This is not a physical
iPhone, cold-start or energy benchmark.

### Attempted regex guide

A preliminary six-call pilot also tested a String regex restricting the paragraph
to 30–60 whitespace-separated ASCII words. Two guide requests failed immediately.
A separate one-call confirmation identified `LanguageModelError.unsupportedGenerationGuide`
with `UnsupportedGuide`. This is evidence that the **tested guide** was rejected
in this model/configuration, not proof that every possible regex is unsupported
and not a guardrail/refusal error.

That arm was stopped before the main comparison. The pilot's six generations and
the confirmation generation are archived separately; none is silently retried or
mixed into the main comparison. No unsupported-guide fallback is added to production.

## Results

| Metric | directID | instructedEssay |
| --- | ---: | ---: |
| Valid ID generation | 48/48 | 48/48 |
| Entire response passes protocol | 48/48 | 42/48 |
| Length violations | not applicable | 6/48 |
| Usable arbitrary selections | 24/24 | 22/24 |
| First-position choices among usable arbitrary selections | 24/24 | 22/22 |
| Correct semantic labels before protocol filtering | 12/12 | 12/12 |
| Usable correct semantic outputs, including length requirement | 12/12 | 8/12 |
| Correct missing-fact abstention | 2/8 | 2/8 |
| Unsupported selections on missing-fact tasks | 6/8 | 6/8 |
| Median observed latency, all attempts | 0.469 s | 1.586 s |
| Maximum observed latency | 1.286 s | 2.500 s |

Every raw arbitrary selection, including the two short essay responses, chose the
first listed option: 24/24 in both arms. None of the twelve paired arbitrary forms
(six forms × two repeats) selected the same actual word across both option orders.
These are position-sensitivity observations; arbitrary tasks have no correct label.

All four bare forms selected an option in both strategies. Both repeats of each
question yielded the same selected word per strategy on this fixed greedy run.

Essay word counts were **23–49**, median **38**. Six short outputs were the same
three cases in both repeats:

- Reversed any-color: 23 words.
- Reversed star control: 28 words.
- Original-order shipment control: 28 words.

The four semantic-control length violations still contained the correct label;
we reject their protocol rather than mislabeling them as semantic mistakes.
There were no generation errors in the main comparison. Completion of an observer
test is not a claim that all model outputs passed the length or behavioral contract.

## Observed explanation problems

The essays are genuine longer outputs in 42 cases, rather than the previous
4–17-word notes. More text still did not establish better reasoning:

- One response called both Hello and Kitty greetings, which is incorrect.
- One birth-city essay acknowledged missing personal details and then selected
  London because it was the first option.
- Coin-toss essays correctly described lack of predictability but still returned
  heads. We count these as unsupported forecasts, not demonstrated false outcomes.

The valid-length birth-city essays returned London in one order and undetermined
in the other. directID returned undetermined in one order and Paris in the other.
Neither strategy handled the missing fact reliably; overall abstention was equal.

## Conclusion

The required longer text did not rescue the chosen-ID strategy on this workload.
Schema-valid output, a plausible comparison, and even a correct statement that
information is missing do not ensure an appropriate final answer. The length
instruction itself also remains imperfectly followed.

Do not deploy this as a new Apple decision adapter on the strength of this run.
The evidence is limited to this corpus, local model/configuration, greedy sampling
and two repeats. It does not rank all Apple models or establish calibration.

The next useful baseline would be a bounded run of the same frozen decision tasks
on a decision-specialized backend, with hosted inference explicitly authorized and
budgeted. Further essay-length tuning is not supported by an observed benefit here.

## Artifacts and reproduction

- [Main raw rows](ORACLE_LONG_ESSAY_2026-10-25.jsonl): 96 generations, including
  invalid-length outputs and their original IDs. SHA-256:
  `9d22226f17d0945390e9791ef6ec861c9d5e140a2cbdef5e057d8c750e1a968a`.
- [Separate pilot and capability probe](ORACLE_LONG_ESSAY_PROBE_2026-10-25.jsonl):
  seven exploratory generations, explicitly phase-labeled.
- Main harness source SHA-256 before the run:
  `787e4bb81af70274d943acfc635f7f91fa409d13ce111b04b022378ae3817e7b`.
- Summed main generation time: 100.804 seconds, excluding process/build overhead.

```sh
# Main comparison: batches 0..15
ORACLE_LONG_ESSAY=1 ORACLE_LONG_ESSAY_BATCH=0 \
swift test --filter OracleLongEssayDiagnosticTests

# Separate one-call guide capability probe
ORACLE_LONG_ESSAY=1 ORACLE_LONG_ESSAY_GUIDE_PROBE=1 \
swift test --filter OracleLongEssayDiagnosticTests
```

Apply repository-required TB5 scratch/cache paths on this workstation. Default
tests validate word-count boundaries and the corpus, and skip local inference.
Full offline suite passed; production/dependency configuration remains unchanged.

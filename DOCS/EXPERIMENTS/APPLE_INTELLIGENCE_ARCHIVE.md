# Apple Intelligence decision pilot — deferred

**Status: deferred on 2026-10-25 at the owner's request.**
Oracle [PR #68](https://github.com/SoundBlaster/SwiftDecision-Examples/pull/68)
and adapter [SwiftDecision PR #22](https://github.com/SoundBlaster/SwiftDecision/pull/22)
were closed without merging. Both remote branches are retained with code, tests,
fixed corpora, reports and raw results. This is an archived experiment, not a release.

## Preserved references

| Repository | Retained branch | Last inference-work snapshot |
| --- | --- | --- |
| SwiftDecision-Examples | `codex/oracle-foundation-models-pilot` | `b98c56f52f7ce7bd1a9ccfa2940538f883e06533` |
| SwiftDecision | `codex/foundation-models-backend` | `1ba00d05d8a499dfffad9628ff7ccd141557219c` |

Oracle pins adapter implementation `f962479c6251e9da224ef159181ae43a1f4cacbd`.
Later archival commits only add status/index documentation. The immutable snapshots
above preserve the exact implementation and evidence before archival.

## Application experiment index

- [Pilot integration, provider selection and device evidence](../ORACLE_APPLE_INTELLIGENCE_PILOT.md).
- [Original first-option / 67:33 diagnostic](../ORACLE_CHOICE_ORDER_DIAGNOSTIC.md).
- [Exploratory wording run](ORACLE_WORDING_2026-10-25.md): historical Russian input.
- [English-only wording and instruction ablation](ORACLE_ENGLISH_INSTRUCTIONS_2026-10-25.md).
- [Initial note-before-ID experiment](ORACLE_ESSAY_2026-10-25.md).
- [Matched instructions and note order](ORACLE_MATCHED_ESSAY_2026-10-25.md).
- [Required 30–60-word essay](ORACLE_LONG_ESSAY_2026-10-25.md).

Six tracked raw files contain 451 rows in total. These include repeated conditions,
post-hoc controls and capability probes; they are not 451 independent benchmark
questions and must not be pooled into one accuracy percentage.

| Raw artifact | Rows | SHA-256 |
| --- | ---: | --- |
| [Wording](ORACLE_WORDING_2026-10-25.jsonl) | 54 | `c113a76289906165dbb0c8e687cd55d3d2c6a7b8b906d2236bb30e5a4aff31f3` |
| [English instructions](ORACLE_ENGLISH_INSTRUCTIONS_2026-10-25.jsonl) | 102 | `5bdc00e30ce467d7a595d7d69f93d3890bc0bcb95f69b117bb4a27c49b05e544` |
| [Initial note](ORACLE_ESSAY_2026-10-25.jsonl) | 48 | `c1118115b8e643116b07b7cd600742e8d9cc0e7fe86a40fd154af3440eae94a0` |
| [Matched note](ORACLE_MATCHED_ESSAY_2026-10-25.jsonl) | 144 | `eeb73d29877c6833e9919a54540a2e08eba12e7f12a286e6c4d2542280330870` |
| [Long essay](ORACLE_LONG_ESSAY_2026-10-25.jsonl) | 96 | `9d22226f17d0945390e9791ef6ec861c9d5e140a2cbdef5e057d8c750e1a968a` |
| [Separate pilot/probe](ORACLE_LONG_ESSAY_PROBE_2026-10-25.jsonl) | 7 | `5a056b939b0caf33519da64e9180a71c31e55bb2b0591deca36ec5bb05ef051a` |

## Adapter evidence retained in SwiftDecision

Immutable snapshot links:

- [Adapter documentation](https://github.com/SoundBlaster/SwiftDecision/blob/1ba00d05d8a499dfffad9628ff7ccd141557219c/Documentation/FoundationModelsBackend.md).
- [Original 48-case output-contract report](https://github.com/SoundBlaster/SwiftDecision/blob/1ba00d05d8a499dfffad9628ff7ccd141557219c/Documentation/Reports/FoundationModelsOutputContracts-2026-10-24.md).
- [Assessment strategy report](https://github.com/SoundBlaster/SwiftDecision/blob/1ba00d05d8a499dfffad9628ff7ccd141557219c/Documentation/Reports/FoundationModelsAssessment-2026-10-25.md)
  and [raw matched comparison](https://github.com/SoundBlaster/SwiftDecision/blob/1ba00d05d8a499dfffad9628ff7ccd141557219c/Documentation/Reports/FoundationModelsAssessment-2026-10-25.jsonl).
- [Fixed corpora and provenance](https://github.com/SoundBlaster/SwiftDecision/tree/1ba00d05d8a499dfffad9628ff7ccd141557219c/Tests/SwiftDecisionTests/Fixtures).

## Reason for deferral

The tested on-device configuration was sensitive to prompt/schema/order changes,
used positional templates for arbitrary choices, and could supply unsupported
answers despite acknowledging missing information. Longer explanations did not
improve final selection on the tested workload and increased latency. Structured
output validity did not establish decision quality or calibrated confidence.

These findings concern the recorded SystemLanguageModel.default configuration on
macOS 27.0 / Xcode 27.1. They do not establish a ranking of all Apple models, future
model versions or all supported tasks. Physical-device launch evidence is separate
from the Mac inference benchmark evidence in each report.

## Resume after a model update

1. Identify the new model/OS/configuration and record it; a newer SDK alone does
   not establish improved decisions. The old API exposes no stable checkpoint ID.
2. Reuse the frozen corpora and English instructions before tuning new prompts.
3. Check schema/length contracts, objective semantic controls, unsupported-fact
   abstention and permutation sensitivity separately. Arbitrary choice has no
   factual answer label and must not be scored as factual accuracy.
4. Retain malformed/short outputs, timing and raw results; do not retry invisibly,
   invent one-hot confidence or conceal unsupported answers with fallback.
5. Reopen or supersede the closed PRs only after reviewing the new evidence.

Live local inference remains opt-in. Hosted comparison would require separate
authorization and a bounded budget. This deferral does not schedule monitoring.

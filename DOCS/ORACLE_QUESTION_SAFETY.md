# Oracle question safety screen

Oracle locally screens a bounded set of explicit English and Russian phrases
about self-harm and harm to people before invoking a model or producing a random
or fallback answer. A match returns a typed safety intervention. The app clears
the previous ball answer and presents support guidance, without sending the
question to a provider or adding it to answer history.

An ambiguous, context-free question such as “Прыгать или нет?” may refer to
either recreation or imminent danger. Oracle displays a neutral abstention and
asks for context instead of inferring intent or returning an arbitrary answer.
When a jump is explicitly associated with selected hazardous places, Oracle
presents safety support instead.

The built-in phrase screen and optional lexicon are not a general moderation or crisis detection
model. They can miss paraphrases, implicit intent, other languages, spelling
variants and context, and it can also match benign discussion. It must not be
represented as comprehensive protection. Expanding coverage requires a
separately evaluated classifier, a representative test corpus, and a review of
false positives, privacy, offline operation, and appropriate support guidance.

## Private local phrase lexicon

The optional lexicon is authored locally as `private/OracleSafetyLexicon.json`.
Both that file and the packed app resource
`Sources/OracleGame/Resources/OracleSafetyLexicon.private.bin` are ignored by
Git. Neither is included in a fresh checkout; the built-in guard remains active
when the resource is absent. A corrupted or invalid *present* resource prevents
nonempty questions from reaching a provider, with a visible unavailable status.

Create the `private` directory and JSON file yourself. The schema is:

```json
{
  "version": 1,
  "entries": [
    {
      "category": "ambiguousRisk",
      "examples": ["replace this with a representative phrase"]
    }
  ]
}
```

Available categories are `selfHarm`, `harmToPeople`, `dangerToLife`, and
`ambiguousRisk`. The first three show support; the last shows a neutral answer
and asks for context. The placeholder above is not a safety dataset: replace it
with your own reviewed examples before packing. An empty `entries` array is
valid but adds no coverage.

From this checkout, run:

```sh
mkdir -p private
# Create or edit private/OracleSafetyLexicon.json before packing.
python3 scripts/pack-oracle-safety-lexicon.py
git check-ignore -v private/OracleSafetyLexicon.json Sources/OracleGame/Resources/OracleSafetyLexicon.private.bin
```

The script validates the format and atomically creates the packed resource. It
contains masked UTF-8 with a checksum; this prevents casual text inspection but
is **not encryption**, and the checksum is not an authenticity signature. A
person with the app and the unpacking logic can recover the content. Never put
credentials or real people's sensitive data in the lexicon. Only the packed
resource, not the source JSON, is packaged into a build made from this checkout.
Other machines and CI need the private source and packing step separately;
otherwise those builds have only the built-in guard. Verify actual artifacts
before distribution.

The matcher runs on device before model inference and before random fallback.
BM25 ranks examples using token overlap. After removing common words, a match
requires at least two matching distinct terms (or one for a single-term example)
and at least 75% of the example's distinct terms. Support categories take
precedence over ambiguous matches; within each priority, the highest BM25 score
wins. The score is not a probability and is independent of the GLiNER confidence
slider.
The initial rule is a heuristic, not a calibrated safety guarantee. It does not
understand meaning, intent or negation, and it does not handle arbitrary
paraphrases, inflections or languages. Review false positives and false
negatives against separate representative examples before relying on a lexicon.

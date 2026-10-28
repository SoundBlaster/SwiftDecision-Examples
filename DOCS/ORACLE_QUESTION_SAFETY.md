# Oracle question safety screen

Oracle locally screens a bounded set of explicit English and Russian phrases
about self-harm and harm to people before invoking a model or producing a random
or fallback answer. A match returns a typed safety intervention. The app clears
the previous ball answer and presents support guidance, without sending the
question to a provider or adding it to answer history.

An ambiguous, context-free question such as “Прыгать или нет?” may refer to
either recreation or imminent danger. Oracle asks for context rather than
inferring intent or returning an arbitrary answer. It also asks for context
when a jump is explicitly associated with selected hazardous places.

This is a phrase-based screen, not a general moderation or crisis detection
model. It can miss paraphrases, implicit intent, other languages, spelling
variants and context, and it can also match benign discussion. It must not be
represented as comprehensive protection. Expanding coverage requires a
separately evaluated classifier, a representative test corpus, and a review of
false positives, privacy, offline operation, and appropriate support guidance.

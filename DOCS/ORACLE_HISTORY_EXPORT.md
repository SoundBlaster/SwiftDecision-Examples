# Oracle history export

Use the share button next to **History** in Oracle settings to export every
currently saved entry. Open an entry's **Decision pipeline** and use its share
button to export that question alone. Choose **Export JSON** or **Export text**,
then use the system share sheet, including Save to Files when available.

The export is an immutable snapshot. It does not clear history, repeat a request
or change the selected inference provider. The app retains at most 50 history
entries by default; export includes the entries that are actually saved, not
deleted entries or requests that never produced a history item. Import is not
part of this feature.

## JSON contract, schema version 1

The UTF-8 `.json` file has these top-level fields:

- `schemaVersion`: `1`.
- `dateEncoding`: `secondsSince1970`; all JSON dates are numeric Unix seconds.
- `exportedAt`: the time the transfer payload is produced.
- `appVersion` and `appBuild`: the exporting app, when Bundle metadata exists.
  These do not identify the app version that originally answered each question.
- `entries`: the saved entries in their existing newest-first order.

Each entry retains its UUID, original question and displayed answer, mode,
provider/source, optional numeric confidence, creation time and optional
pipeline. Pipeline stages retain their details, lifecycle events, curated
SpecificationCore events, IDs, parent IDs, durations, and the saved ordered
timeline. Integer elapsed/duration values remain nanoseconds. Order is preserved
within each stage; timelines from separate calls are not flattened together.

Newly answered decisions also retain a `distribution` per decision stage:

```json
{
  "options": ["red", "blue"],
  "probabilities": [0.123456789, 0.876543211],
  "confidence": 0.876543211
}
```

Options and scores remain aligned in the original caller order. This captures
SwiftDecision's returned numeric result before display rounding, not raw model
logits or new probability calibration. It does not alter inference or acceptance
policy. Automatic intent classification and explicit Noul/Choice/Score decisions
are captured, including simulation decisions when they produce saved history.

Existing history may contain only display-rounded distributions in its detail
strings, or no pipeline at all. Export preserves that absence and does not
invent missing precision, events, logits, prompts or backend configuration.

## Plain text

The UTF-8 `.txt` report contains the same saved evidence in labeled sections,
with UTC timestamps, full numeric scores, stage IDs and trace relationships.
Report field labels are English; original questions, answers and saved detail
strings are kept in their original language. Text is not interpreted as HTML
or Markdown. JSON is the preferred format for exact machine comparisons.

## Data boundary

Only the explicitly supplied history entries and app version/build are read.
The exporter does not read Keychain, credential preferences, network headers,
model files or application settings. Questions and answers themselves are
included because they are the content the user chose to share. Filenames use
`oracle-history` or a question UUID, never the question text.

## Validation

`OracleHistoryExportTests` covers JSON round trips, legacy decoding, Unicode and
multiline text, complete saved timelines, unrounded scores, deterministic
encoding, single-entry selection, empty history, invalid numeric output and
history/credential isolation. `OracleDistributionTraceTests` checks capture and
label alignment for Choice, Noul and Score. The UI uses native `ShareLink` and
`Transferable` data representations with `.json` and UTF-8 text content types.

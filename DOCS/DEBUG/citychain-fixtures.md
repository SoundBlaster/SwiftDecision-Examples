# CityChain debug fixtures

Debug builds can start from a versioned JSON route. The route is restored into
the real `CityChainGame` actor, including canonical city records, used IDs,
continuation records, and the next required letter. Release builds ignore these
arguments.

## Fixture format

```json
{
  "version": 1,
  "route": [
    { "role": "player", "city": "Austin" },
    { "role": "computer", "city": "Nashville" }
  ],
  "draft": "El Paso"
}
```

`route` contains turns in play order and alternates player/computer. Player
cities can be outside the reply catalog; matching catalog cities are restored
with their state/capital metadata. Computer cities must be in
`USCityCatalog.standard`. Names cannot repeat and each turn must follow the
active chain policy. `draft` pre-fills the next player input; `focusInput` can
open the keyboard for capture. Schema errors and invalid routes appear in a
startup alert.

Supported `phase` values are:

- `ready` (default): even number of turns; ready for the next player move.
- `thinking`: odd number of turns ending with a player city. This is a paused
  screenshot state, with no model request running. Use the **Exit capture**
  toolbar action to reset it and return to a playable new round.
- `feedbackAccepted` and `feedbackRejected`: even number of turns, with an
  optional `feedbackMessage`; Scout's feedback can be dismissed normally.
- `finished`: odd number of turns ending with a player city, and a required
  `ending` value (`computerAbstained` or `noAvailableReply`). The latter is
  checked against the catalog. `endingMessage` optionally sets the visible
  reason.

## Launch from the open Xcode workspace

The app sandbox cannot read an arbitrary macOS path. Copy the fixture into the
simulator app's Documents folder, then add these two entries under **Product →
Scheme → Edit Scheme → Run → Arguments Passed On Launch**:

```text
-citychain-fixture-file
<simulator app Documents path>/citychain-route-v1.json
```

Choose the exact simulator from `xcrun simctl list devices booted`; with several
simulators booted, `booted` is ambiguous. Set `SIMULATOR_ID` to that device's
UDID, then get the app Documents path and copy the example fixture:

```sh
SIMULATOR_ID="<Duo simulator UDID>"
APP_DATA="$(xcrun simctl get_app_container "$SIMULATOR_ID" com.soundblaster.citychain data)"
cp DOCS/DEBUG/citychain-route-v1.json "$APP_DATA/Documents/citychain-route-v1.json"
```

For a quick launch without editing the scheme, use the same arguments directly:

```sh
xcrun simctl launch "$SIMULATOR_ID" com.soundblaster.citychain \
  -citychain-fixture-file "$APP_DATA/Documents/citychain-route-v1.json"
```

There is also `-citychain-fixture-json` followed by the complete JSON string,
which works in Xcode's launch arguments and avoids copying a file. If both
selectors are present, inline JSON takes precedence.

The included route ends at New Orleans with `S` required and `Springfield`
pre-filled, so the screen opens mid-game and remains ready for the next move.

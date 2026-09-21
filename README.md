# SwiftDecision Examples

Small applications that demonstrate model decisions composed with `SpecificationCore` rules.

## City Chain

City Chain is an offline-testable game engine for a US cities word chain. The player may enter any city name; Noul checks whether it is a US city. The built-in catalog is only used for computer replies and contains the 50 state capitals plus 50 additional large cities.

The engine composes Core rules to reject empty input, enforce the current starting letter, prevent reuse, filter computer replies, and route between no reply, one automatic reply, and a model-selected reply. SwiftDecision uses Noul for player-city validation and Choice to select among at most five legal candidates. An abstention remains visible as a game outcome, and backend errors are thrown without partially committing a turn.

The game engine has no UI or live model requirement, so its rule combinations run offline with a deterministic request/response backend:

```sh
swift test
```

The engine package supports iOS 13+ and macOS 10.15+. A SwiftUI example app can use it as its domain layer.

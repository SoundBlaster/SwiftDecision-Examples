# SwiftDecision Examples

Small applications that demonstrate model decisions composed with `SpecificationCore` rules.

## City Chain

City Chain is an offline-testable game engine for a US cities word chain. The player may enter any city name; Noul checks whether it is a US city. The built-in catalog is only used for computer replies and contains the 50 state capitals plus 50 additional large cities.

The engine composes Core rules to reject empty input, enforce the current starting letter, prevent reuse, filter computer replies, and route between no reply, one automatic reply, and a model-selected reply. SwiftDecision uses Noul for player-city validation and Choice to select among at most five legal candidates, taken in stable catalog order. If Choice inference fails, the engine randomly selects from those same candidates. Noul abstentions remain visible as game outcomes, while Noul errors still propagate without partially committing a turn.

The game engine has no UI or live model requirement, so its rule combinations run offline with a deterministic request/response backend:

```sh
swift test
```

The engine package supports iOS 13+ and macOS 10.15+. A SwiftUI example app can use it as its domain layer.

## Optional TypeSafe Jev backend

The package resolves [`SwiftJev 0.1.0`](https://github.com/SoundBlaster/SwiftJev/releases/tag/0.1.0) alongside [`SwiftDecision 0.2.0`](https://github.com/SoundBlaster/SwiftDecision/releases/tag/0.2.0). The game remains offline by default; choose the hosted provider explicitly through `CityChainBackendFactory` when a caller has configured a key:

```swift
let backend = try CityChainBackendFactory.makeJev(apiKey: apiKey)
let game = CityChainGame(decisions: DecisionEngine(backend: backend))
```

`makeJev` performs configuration validation and does not send a request during initialization. Keep the API key outside source control and inject it from the app's development or deployment secret configuration. The existing SwiftUI app uses the offline backend until its `AppDependencies` is constructed with a live backend.

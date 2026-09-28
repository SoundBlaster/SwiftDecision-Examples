# CityChain automatic save

CityChainApp keeps one automatic save at
`Application Support/CityChain/autosave-v1.json`. It stores a versioned game
fixture with the current route, input draft, and visible turn feedback. There
are no profiles or save slots. Scout's no-repeat fact identifiers remain in
their existing, independent UserDefaults entry.

The file is replaced with an atomic write when the player edits the draft,
starts a submission, completes a turn, dismisses feedback, or starts a new
round. Starting a submission writes the previous completed route and the
submitted city as the draft. If the process exits while the model is checking
the city or choosing a Scout reply, launch restores that route and draft in a
ready state; it does not resume a stale spinner or add a partial turn. A
completed result then replaces the save with the newly completed route,
including a finished round when Scout cannot reply.

Missing, malformed, unsupported-version, and invalid-route data cannot prevent
launch. The store ignores malformed or unsupported JSON. The game actor checks
all route constraints into temporary values before replacing live state, so an
invalid route cannot partially restore a game.

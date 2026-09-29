# CityChain automatic save

CityChainApp keeps one logical automatic save at
`iCloud Documents/Documents/CityChain/autosave-v1.json`, in container
`iCloud.com.soundblaster.citychain`. If iCloud is unavailable or a coordinated
cloud access fails, it falls back to
`Application Support/CityChain/autosave-v1.json`. It stores a versioned game
fixture with the current route, input draft, visible turn feedback, mistake
count, and hint. There are no profiles or save slots. Scout's no-repeat fact
identifiers remain in their existing, independent UserDefaults entry.

Envelope version 2 records `savedAt`; version 1 saves remain readable and are
assigned the oldest timestamp during migration. On launch, the app validates
candidate routes newest first across both locations, using iCloud first when
timestamps tie. Writes still try iCloud first and use Application Support only
when cloud access fails. A newer local route is promoted to iCloud when the
cloud item is writable, so an older cloud copy cannot replace newer local-only
progress on the next launch. Timestamps use each device's wall clock.

Container lookup and file access run away from the UI actor. Reads and writes
for the ubiquitous file use `NSFileCoordinator`; writes are atomic. Reads
return cloud and local candidates in priority order so the game engine can
validate each route. Corrupt, unsupported, or invalid cloud data falls through
to a valid local save. Before reading, the app checks the ubiquitous item's
download status. A `.notDownloaded` placeholder triggers
`startDownloadingUbiquitousItem(at:)`; while download is pending or cloud
availability is unclear, the app uses local data without promoting or writing
over the cloud item. A local save used for recovery is promoted back to the
cloud only when the cloud item is known to be readable or absent.

The file is replaced when the player edits the draft, starts a submission,
completes a turn, dismisses feedback, or starts a new round. Starting a
submission writes the previous completed route and submitted city as the
draft. If the process exits while the model checks the city or chooses a Scout
reply, launch restores that route and draft in a ready state; it does not
resume a stale spinner or add a partial turn. A completed result replaces the
save with the newly completed route, including a finished round when Scout
cannot reply. If cloud and local writes both fail, the app surfaces the
persistence error in the status message.

Missing, malformed, unsupported-version, and invalid-route data cannot prevent
launch. The store ignores malformed or unsupported JSON. The game actor checks
all route constraints into temporary values before replacing live state, so an
invalid route cannot partially restore a game.

Concurrent edits from multiple devices are not merged. Coordinated atomic
writes serialize file access on each device, and the intended conflict policy
is last writer wins. The app does not inspect or resolve iCloud conflict
versions, so it cannot guarantee that simultaneous edits from different
devices collapse to one route until conflict-version handling is added.

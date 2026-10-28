# Oracle simulator visual traces

This opt-in development project records bounded local Screener traces for Oracle
without adding Screener to the ordinary Oracle app, TestFlight, or App Store
build. It uses ScreenerKit 0.2.0 and a separate simulator bundle ID
`ru.egormerkushev.oracle.screener`. The probe compiles only with `DEBUG`,
`ORACLE_SCREENER`, and `targetEnvironment(simulator)`; it starts only when
`ORACLE_SCREENER_RECORD=1` or `ORACLE_SCREENER_RECORD=layout` is present at launch.

## Build

On the TB5-configured development machine, install XcodeGen and run:

```sh
python3 scripts/oracle-screener-build.py --device <exact-simulator-uuid>
```

The script checks TB5, copies tracked sources and Screener inputs into a new TB5
snapshot, generates the separate project there, and builds with per-checkout
DerivedData and package paths. It does not regenerate the ordinary project or
rewrite its `Package.resolved`. It prints the snapshot and app paths; old
snapshots remain on TB5 for inspection. The helper uses the local
`tb5-build-cache` skill and fails if it is unavailable. The simulator app is
unsigned and is not a device or TestFlight artifact.

## Capture and inspect

1. Install the printed app on the **same explicit simulator** and launch it with
   `SIMCTL_CHILD_ORACLE_SCREENER_RECORD=1` (or `layout`) and
   `SIMCTL_CHILD_ORACLE_DUO_LAYOUT_PILOT=1` in the `simctl` environment.
2. Reproduce the desired scenario using synthetic question and history data.
   With `1`, recording starts after the app's window attaches. It takes a frame at most
   every four seconds in a stable layout and requests an eight-frame burst on
   a semantic layout change, subject to encoding time. It stops after 180 seconds
   or 40 frames. A 100 ms sleep between burst attempts is not a frame-rate guarantee.
   With `layout`, the probe waits up to 15 minutes for a layout change, then
   records a separate short trace for each change and rearms. The trigger records
   the previous layout in `triggeredFrom`; it does not include pre-change images.
   Sample metadata also includes scene scale, size, and positions, without question text.
3. To stop early, get the simulator app-data container with
   `xcrun simctl get_app_container <uuid> ru.egormerkushev.oracle.screener data`,
   then create `Library/Caches/OracleScreener/stop` in that container while a
   trace is recording. Wait for the trace's `sessionEnded` record; abrupt
   termination may leave an incomplete trace. In `layout` mode, stop the app
   after the short trace closes to cancel the waiting probe.
4. Find the desired UUID under the container's `Library/Caches/OracleScreener/Traces`.
   Export a closed, non-empty trace to the default local MCP catalog:

   ```sh
   python3 scripts/oracle-screener-export.py --device <uuid> --trace <trace-uuid>
   ```

   Export refuses incomplete, failed, or already existing traces. Call
   `screener.sessions`, `screener.timeline`, and `screener.contact_sheet` or
   `screener.frame` with the returned session ID.

The trace contains screenshots of the app and can include questions and answers;
keep captures local and use synthetic input when sharing. `UIKitCaptureSource`
records window hierarchy images, not compositor video. On the tested simulator it
rendered the RealityKit ball, but this does not establish fidelity for all frames,
materials, devices, or OS versions. For fast transitions and final appearance,
pair the trace with an independent simulator display recording, explicitly
identifying the active inner/outer display. The trace and system recording have
separate timestamp domains.

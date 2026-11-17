# Audit work list

Open items from the November 2026 performance and reliability audit of the whole app, plus the
Automation zoom/pan feedback from testing. Items are ranked by user impact within each section.
Line numbers are approximate and drift as code changes; the symbol names are the reliable anchor.

Each item: where it is, what goes wrong, the proposed fix, and how to check it. Size is a rough
guess (S = under an hour, M = a few hours, L = a day or more).

Already fixed in the same pass (on `fix/live-transcription-pco-automation-perf`, uncommitted at
the time of writing) and not repeated here: Resolume zero-length poll sleep, LAN service no-op
publishes, LAN request timeout, OSC recent-address snapshot churn, linked/synced variable no-op
writes, Sennheiser no-op writes, RTA/Spectrogram controllers retained forever, autosave write
ordering, PCO live refresh not starting, Exit Live Mode triggers, Toggle/Counter/Sequence/Latch
state lost on persist, keystroke trigger data race, compact-card size pop.

---

## 0. Needs a decision first

- [x] **Automation view: triggers could run twice, or not at all** — fixed
  - `GraphAutomationRuntime` is now the only executor, in Canvas and Automation view: the root
    keeps it enabled (it used to disable it outside Canvas while the Automation view re-enabled
    it), and the Automation view no longer runs `runActionsDownstream` on
    `TriggerNodeNotifications.fired` / `.triggerNodeDidFire`. The runtime already de-duplicates
    the duplicate posts trigger nodes send on both buses (shared 0.2 s window), and its flow
    covers everything the view's executor did (variables, actions, console actions, Repeater,
    Delay) plus Toggle/Counter/Sequence/Latch.
  - The root's tab provider no longer returns `nil` outside Canvas, and the root now registers
    a graph updater, so runtime results (variable values, utility node state) are saved in Canvas
    mode even if the Automation view was never opened.
  - **Not verified in the app:** firing a trigger in Automation view. The test dashboard's only
    harmless trigger is a canvas button; its other triggers send OSC to real devices.

## 1. Automation view smoothness

- [x] **Zoom and pan with detailed nodes rebuilt every node on every frame** — fixed
  - `GraphDashboardCanvasView` and the graph scene passed `$store.pan` / `store.zoomBinding`
    into `.viewportPanZoom` and `ViewportPanZoomControls`. SwiftUI compares a child's `Binding`
    inputs by reading their values in the parent's update, which subscribed those large bodies
    to pan/zoom: ~1,200 `ModuleGroupNodeView` rebuilds per 7 s gesture. Bindings are now built
    inside `GraphViewportPanZoom` / `GraphViewportZoomControls`; rebuilds dropped to ~15.
    Node size measurement also pauses during gestures (`GraphNodeSizeReporter`).
  - Benchmark (scripted zoom+pan at 100%, 15-node dashboard, accessibility client attached):
    worst frame ~500–700 ms → ~150 ms; typical late frame 33 ms → 8 ms.
  - Tried and dropped (no measurable gain): culling off-screen nodes; an equatable wrapper
    around `GraphDashboardView`.

- [x] **The whole graph re-rendered every ~5 s with nothing changed** — fixed
  - **Cause:** `SharedValueStore` persisted all shared values into `UserDefaults` every ~5 s
    (live wireless and clock values change constantly). Every `UserDefaults` write notifies
    every `@AppStorage` in the app, and `GraphDashboardView` has three, so the whole graph
    (~100–150 ms) and every other `@AppStorage` view re-rendered on each save.
  - **Fix:** shared values are stored in `Application Support/Relay/SharedValues.json`
    (`FileSharedValueStorage`), with identical saves skipped. The legacy `relay_shared_values_v1`
    key, whether from an older build or a `PreviousRelayImporter` import, is moved into the file
    on load and removed. Measured: 0 graph re-renders in 30 s of idle Automation, was one every
    ~5.3 s.
  - **Ruled out on the way:** document (`tabs`) writes, the per-render tab `Binding`
    (`_printChanges` reports a custom binding as changed on any update), the persistence task
    property itself.
  - Also done: `scheduleTabsSaveDebounced` now writes `tabs` only when Button trigger
    reconciling changed something.
  - Left as is: `refreshPCOModulesForSelectedTab` rewrites PCO modules with an identical value
    on purpose to force PCO tiles to redraw.

- [x] **Shared-values snapshot published 3–4 times a second** — fixed
  - `SharedValue.apply` refreshes `lastUpdatedAt` for an unchanged live value once a second, so
    nearly every refresh tick produced a new snapshot. `SharedValueStore.publish(_:)` is now the
    only publish point; a snapshot that differs only in `lastUpdatedAt` is published at most
    every 5 s, while payload, status, value-list and recent OSC/trigger changes publish
    immediately. Measured on the test dashboard (1,240 values): 74 → 24 publishes per 20 s.
  - The remaining ~1/s publishes are the clock values (`clock_local_time`,
    `clock_unix_timestamp`), which genuinely change every second.

- [x] **Every shared-values reader re-rendered on any value change (e.g. the clock, every
  second)** — fixed
  - `SharedValueStore.value(named:)` returns a value through a small per-name observable cell
    (`SharedValueCell`), updated on publish only when that name's payload or status changes.
    `SharedValueResolver` uses it, and text-tile token resolution
    (`GraphRuntime.resolveTextInterpolationToken`) now looks tokens up with
    `GraphRuntime.variableValue(forKey:tab:)` instead of building the full
    `variableValuesByName` dictionary (all ~1,240 values) for every token on every render.
  - Still whole-snapshot readers (fine, not per-frame): the Shared Values window, token
    autocomplete and the inspector's variable list, and the LAN export.
  - Verified by `SharedValueObservationScopeTests`: a reader of `#clock_weekday` isn't notified
    when the clock ticks, and is notified when the weekday changes. Not measured in the app (the
    test dashboard has no text tiles).

- [x] **Other `UserDefaults` writers re-rendered every `@AppStorage` view** — fixed
  - Measured with a temporary `UserDefaults.didChangeNotification` logger on FOH NEW: 0 writes
    in 90 s of idle, so the shared-values file move removed the only steady writer on this
    machine. Opening a document caused 41 writes, now 9: AppKit's own 3, plus 6 `@AppStorage`
    assignments made once at launch.
  - **Fixes:** `UserDefaults.setIfChanged(_:forKey:)` / `removeIfPresent(forKey:)` skip
    identical writes, used by `applySettingsSnapshot` (about 20 keys on every document open),
    `NDIPreferencesStore`, `ResolumeProfilesStore`, `ExternalDevicesStore`, the audio and
    transcription input stores, canvas size presets, the hidden-tiles flag (written on every
    tile change) and the window frame. `DashboardRootView.init` also removed two legacy keys on
    every re-init.
  - `JSONEncoder` key order varies between runs, so identical values encoded to different bytes
    and defeated the comparison. Those payloads now use `JSONEncoder.stableKeyOrder()`
    (sorted keys).
  - `ResolumeProfilesStore.load()` saved a half-loaded state twice (once per property
    assignment); saves are now suppressed while loading.
  - Shure live sync still stamps "last synced" while a receiver is online, but every 5 min
    instead of every 30 s (`ShureWirelessService.liveSyncPersistInterval`). Not checked with a
    live receiver.

- [x] **Per-frame cost: native controls under the zoom transform** — fixed, interaction not yet
  verified in the app
  - **Measured before:** a scripted zoom/pan at 100% on FOH NEW took 100–160 ms per frame with
    the main thread ~98% busy; the same zoom on compact cards (no native controls) stayed under
    42 ms. Earlier "median 8 ms" numbers counted idle frames and hid this.
  - **Cause:** SwiftUI applies `scaleEffect` to each AppKit-backed control (`TextField`,
    `Picker`, `Stepper`, `Toggle`, bordered `Button`, the variable token field's `NSTextView`)
    with `setFrameTransform`. AppKit treats every scale change as a backing-property change, so
    the controls re-measure, which threw away the node layout caches: each frame re-measured
    every node form (visible as `SecondaryLayerGeometryQuery` → `sizeThatFits` in samples).
    Ruled out on the way: the `GraphSceneSpace` coordinate space and the zoom controls overlay.
  - **Fix:** graph nodes use SwiftUI-drawn controls from `GraphNodeControls.swift`, with the
    native initializers so call sites only changed the type name:
    - `GraphTextField` shows the value as text and swaps in a real `TextField` (focused) when
      clicked, back to text when focus leaves. `AutomationVariableTokenField` does the same
      with its AppKit text view (`activatesOnAppear` / `onEndEditing`).
    - `GraphPicker` reads the existing `.tag(...)` content (`ContainerValues.tag(for:)`):
      `.graphPickerStyle(.segmented)` draws inline segments, menu style opens a popover list.
    - `GraphStepper`, `GraphMenu`, `GraphSwitchToggleStyle` / `GraphCheckboxToggleStyle`,
      `GraphPushButtonStyle` / `GraphBorderlessButtonStyle`. `.graphNodeControlStyles()` on
      the node layer covers buttons and (macOS) toggles without an explicit style.
    - Left native: the two OSC trigger fields and the add-node search field (they use
      programmatic focus), and two `Slider`s.
  - **Measured after** (CPU time the app used for the same 3 s scripted zoom, window
    off-screen so no frame timings): about 3.4 s before → 1.2–1.8 s after. Samples no longer
    show the per-frame re-measure.
  - **Trade-offs:** Tab no longer moves between graph fields (the static fields aren't
    focusable); a click places the caret at the end; menu pickers open a popover instead of a
    native menu.
  - **Not verified in the app:** editing a field, choosing from a menu picker, steppers. The
    test window stayed on another Space, where background clicks don't reach it. Frame timings
    on screen are also still to measure.

- [x] **Stall when crossing the compact-card threshold** — reduced
  - Zooming back in past 65% used to build every detailed node in one frame. Detailed forms now
    appear three nodes per frame, nearest the viewport center first
    (`GraphDashboardView.handleZoomedOutChange`); the rest stay as compact cards (same height)
    until their turn. Selected, linking and hover-target nodes still switch at once. Zooming out
    again cancels the reveal.
  - Building detailed nodes is also much cheaper now that they have no native controls: CPU
    for the 50% → 70% crossing benchmark dropped from ~1.3 s to ~0.5 s (both with the stagger).
  - **Not measured:** the stagger on its own (on vs off), and on-screen frame timings.

## 2. High impact

Goal for Shure and Sennheiser: a Wireless Workbench-like live view (battery, frequency, RF and
audio meters) that stays smooth across many receivers. Judge wireless items by that, not only CPU.

- [x] **Shure tiles redraw on every network packet** — fixed, uncommitted
  - **Cause:** tiles hold `ShureWirelessService` as an `ObservableObject`, and the service
    published ~25 per-packet maps (levels, battery, RF, presence, mute, timestamps), so every
    write redrew the tile; names and frequencies were also rewritten every update. In the tile, a
    min/max stat was written each 10 Hz tick but never shown, and the smoothed meter decayed
    toward zero forever, writing (and redrawing) at 10 Hz on a silent channel.
  - **Fix:** the per-packet maps are plain properties whose `didSet` schedules the existing
    throttled `telemetrySnapshot` publish (`telemetryStateDidChange()`: no-op while a publish is
    pending or the snapshot is being built, and not counted as a dropped update, which feeds the
    overview's strain check). Names and frequencies are written only on change. The unused stat is
    gone; the meter snaps to zero near the floor and skips changes under 0.01 (levels run 0–20).
  - **Measured** with live receivers (4 single-channel tiles on MIC3.101 ×2, MIC3.105 and IEM3.101,
    Live mode, 30 s, temporary counters removed afterwards):

    | per second | before | after |
    |---|---|---|
    | frames received | ~400 | ~400 |
    | meter values applied | ~330 | ~330 |
    | service change notifications | ~5,400 | ~60 |
    | tile redraws (all 4) | ~340 | ~23 |
    | app CPU | ~74% of a core | ~35% |

  - **Found on the way** (toward the Wireless Workbench-style goal):
    - Snapshots publish ~20 times a second per receiver, faster than the 0.15 s throttle
      suggests, so some path publishes immediately per update.
    - All packet parsing runs on the main actor (`startReceiveLoop` → `handleIncoming`, ~20% of
      main-thread time for 3 receivers). With ~400 frames/s per 3 receivers, a 23-receiver
      overview would saturate the main thread; parsing should move off it.
    - Meter data reaches tiles through the same snapshot as battery/RF/frequency, so a faster
      meter would redraw the whole tile. A per-channel meter path (only the meter redraws) is the
      next step.

- [ ] **Shure Overview: cost and update rate** — M
  - **Measured** (Preview enabled for the test, then restored; Overview limited to MIC3.101,
    MIC3.105, IEM3.101 and IEM3.105; Live mode, 30 s; no transmitters on at the time):
    - ~31% of a CPU core, the same with and without the tile fix above: the Overview never
      observed the services directly (their change notifications still dropped ~2,900/s → ~14/s).
    - The Overview redrew ~1.3 times a second. With nothing on, the hub runs on its slow tier
      (`baseThrottleInterval`); it only switches to 0.15 s when a channel is on. On-state meter
      cadence is still to measure with a transmitter powered on.
  - **Hot spots on the main thread:**
    - `ShureOverviewHub.refreshThrottleIntervalForActivity()` runs on every snapshot from every
      receiver and calls `hasAnyOnChannel` on all services, which re-resolves transmitter state
      per channel (`resolvedTelemetryTransmitterState`, `shouldTrustFastUdpPresenceEvidence`,
      `isAxientDeviceModel`). Cost grows with receivers × channels × publish rate; the snapshot
      already carries `transmitterState`, so the check can read that, at most a few times a second.
    - ANX4 diagnostic logging (`logAnx4PacketSummary`, `RelayDiagnosticsStore.recordShureTrace`)
      runs in Release builds, ~2.5% of main-thread time.
    - Packet handling on the main actor, as above.
  - **For the Workbench goal:** the Overview's default audio mode is a signal light, not a meter,
    and rows rebuild as one list; per-channel meter state would let meters update without
    rebuilding every row.

- [ ] **ProPresenter tiles redraw 3–5 times per poll** — S/M
  - **Where:** `ProPresenterModule.swift`: `@Published stateByModuleID` (~597) written several times
    per `tick`; `lastUpdated = Date()` always changes; `loadProfile` decodes the profile JSON ~3×
    per tick.
  - **Fix:** build each module's new `State` locally and assign once per tick, only if it changed
    (excluding `lastUpdated` from what drives redraws); use `ProPresenterConnection.loadProfilesCached`.
  - **Check:** 4 ProPresenter tiles at 0.5 s: body count per second drops from ~30–40 to ~8.

- [ ] **DAW Transport polls MIDI at 5 Hz forever** — S/M
  - **Where:** `DAWTransportModule.swift`: `startStatusTimer` (~1944), `updateStatusSnapshot` (~1951);
    `DAWTransportViewModelStore` keeps view models alive.
  - **What goes wrong:** every DAW tile ever shown enumerates CoreMIDI and rewrites ~15
    `@Published` values every 0.2 s, visible or not.
  - **Fix:** refresh ports on CoreMIDI change notifications; write only changed values; pause
    while the tile isn't visible.

- [ ] **Live Transcription redraws at 10 Hz and the transcript grows forever** — S/M
  - **Where:** `LiveTranscriptionModule.swift`: `inputLevel` (~232) published per channel;
    `limitsEnabled: false` by default (~91); full re-sort per partial result.
  - **Fix:** publish `inputLevel` only when diagnostics are shown; insert entries in order; turn on
    a default `maxEntries` (the 400 already defined).
  - **Check:** an hour-long transcription keeps memory flat; tile body count drops at idle speech.

- [ ] **Session log file grows without limit** — S/M
  - **Where:** `RelayLogManager.swift` (~212, stdout redirect `readabilityHandler`); old logs only
    pruned at launch. Release-build prints include full `pushSyncedSnapshot` response bodies in
    `LANSharedTabsService` and `recordError`.
  - **Fix:** roll to a new file at a size cap inside the handler; gate or rate-limit the noisy prints.

- [ ] **Browser-viewer thumbnails render on the main thread every 2 s** — M
  - **Where:** `DashboardRootView.swift`: render loop (~5248), `renderTabImageData` (~5292); writes
    root `@State lanRenderCursor`.
  - **Fix:** keep the cursor in a reference type; render only when the tab changed; encode JPEG
    straight from `CGImage` instead of TIFF→JPEG.
  - **Check:** with an HTTP viewer connected, no 2 s periodic hitch.

## 3. Medium impact

- [ ] **Text tiles redraw on any settings write** — S
  - **Where:** `TextModuleModel.swift` (~386, ~2084): `onReceive(UserDefaults.didChangeNotification)`.
  - **Fix:** observe only the keys console sync depends on (`@AppStorage` or KVO on those keys).

- [ ] **Box-select redraws the whole dashboard on every mouse move** — S/M
  - **Where:** `DashboardRootView.swift`: `@State selectionCurrentPoint` (~355), written per drag event.
  - **Fix:** move marquee start/current points into a small `@Observable` store read only by the
    overlay; commit `selectedTileIDs` on drag end (same pattern as `GraphInteractionStore`).

- [ ] **Every edit pays for redundant `tabs` writes and four `onChange(of: tabs)` handlers** — M
  (the reconcile write is now change-only; the handlers are not yet merged or debounced)
  - **Where:** `DashboardRootView.swift`: `scheduleTabsSaveDebounced` (~8797) writes
    `tabs[i].reconcileButtonTriggerNodes()` for every tab regardless of its result; handlers
    run diagnostics, roster sync, OSC config refresh, PCO coordinator setup per edit.
  - **Fix:** reconcile on a local copy and assign only if changed; merge the handlers; debounce
    diagnostics and OSC refresh; key roster sync on `sharedRosters`.

- [ ] **Keychain reads on the main thread for every LAN request** — S
  - **Where:** `PairingSecretStore.swift` `KeychainPairingSecretStore.secret(for:)`, called from
    `LANSharedTabsService.makePeerRequest` and `evaluateAuthorization`;
    `ProPresenterKeychainStore` via `ProPresenterConnection.init`.
  - **Fix:** in-memory cache invalidated in `setSecret`/`removeSecret`.

- [ ] **MIDI timecode floods the main thread and can show torn values** — M
  - **Where:** `MIDIProcessing.swift` (~507) emits per quarter-frame (~120/s); `TimecodeService.swift`
    (~41–48, ~105) hops to main, publishes 3 properties, and creates a new `Timer` each time. No
    CoreMIDI hot-plug handling (`notifyProc` nil), so devices connected later are ignored.
  - **Fix:** emit after full frames only; publish on change; one repeating timer; add a notify proc.

- [ ] **Peer discovery leaks connections and overlaps polls** — M
  - **Where:** `LANSharedTabsService.updatePeers` (~3496): `NWConnection` only cancelled on
    `.ready`; browser restarted every 10 s; each `mergePeer` kicks an extra poll.
  - **Fix:** cancel on `.failed`/`.waiting` or timeout; stop the periodic restart; coalesce kicks.

- [ ] **Peers are polled one after another** — M
  - **Where:** `LANSharedTabsService` poll passes and `pushSyncedSnapshot`.
  - **What goes wrong:** with the new 5 s timeout one dead peer still delays the rest by 5 s per request.
  - **Fix:** poll peers concurrently with a task group.

- [ ] **SPL meter bookkeeping on the main thread per audio buffer** — S
  - **Where:** `Modules/DbReader/DbReaderController.swift` (~336–416): hops to main before the
    `publishHz` throttle, appends to two 5 s arrays and rescans for the minimum.
  - **Fix:** throttle before hopping; keep a running minimum.

- [ ] **Shure Overview hub refreshes every 3 s, live or not** — S
  - **Where:** `Modules/ShureOverviewHub.swift` (~311, ~621).
  - **Fix:** run the timer only while live; assign only when the channel list differs.

## 4. Correctness

- [ ] **Data race in the X32/M32 OSC client** — M
  - **Where:** `ConsoleConnector.swift`: `X32OSCClient` (~606–790). `configure()` and
    `sendNowOrQueue` mutate `connection`, `isReady`, `pendingSends`, `lastSendAt`, `isConfiguring`
    on the caller's thread while network-queue handlers mutate them too (`@unchecked Sendable`).
  - **Fix:** do all state access inside `queue.async`.
  - **Check:** two automation triggers sending to the console at once, under Thread Sanitizer.

- [ ] **Variables overwritten by stale values after a Delay** — M
  - **Where:** `GraphAutomationRuntime.runDownstreamActions` (~1684/1741) snapshots the graph,
    awaits Delay/Repeater sleeps, then persists; `mergedGraphPreservingEditorState` copies every
    variable value from that snapshot. The Current Time tick persists from cached tabs the same way.
  - **What goes wrong:** a flow with a 5 s delay reverts any variable another trigger set meanwhile.
  - **Fix:** track which variables a run touched and merge only those.

- [ ] **App Launch trigger can run before the document loads** — S/M
  - **Where:** `GraphAutomationRuntime.start()` posts `.relayAutomationDidLaunch` via `main.async`
    (~588) when the shared runtime is created, possibly before
    `syncGraphAutomationRuntimeSnapshots()` has the restored document.
  - **Fix:** post the launch event after the first snapshot that contains the restored document.

- [ ] **ProPresenter TCP fallback can truncate large replies** — S
  - **Where:** `ProPresenterConnection.swift` (~370, ~522): a single `receive(maximumLength: 64_000)`
    treated as the whole reply.
  - **Fix:** keep reading until newline or end of stream.

## 5. Low impact

- [ ] `LANSharedTabsService.receiveHTTP` (~2379) copies the accumulated buffer per 64 KB chunk on
  the main thread (quadratic for big snapshot pushes).
- [ ] `LANSharedTabsService.refreshSettingsCache` (~952) ignores `force` and re-reads UserDefaults
  per request; `minSettingsReadInterval` is unused.
- [ ] `SystemUsageMonitor` publishes `lastMidiActivity` once per MIDI message
  (`SystemUsageOverlayView.swift` ~41); throttle to the 1 s activity window.
- [ ] `GraphAutomationRuntime.recordRuntimeCounter`/`recordRuntimePerf` (~333) spawn a
  `Task { @MainActor }` per OSC/MIDI/transcription event; batch counters on the runtime queue.
- [ ] `DashboardTileEditView.swift` (~2232) writes `shureChannelDescriptors` on every `$devices`
  emission without checking for a change.
- [ ] Resolume: `ResolumeModule` `onDisappear` doesn't stop the shared connection's polling, and
  each pass pretty-prints the whole composition JSON on the main thread for an 800-character
  preview. Stop polling when no Resolume tile is visible; drop the pretty-print.

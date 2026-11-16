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

- [ ] **Automation view: triggers can run twice, or not at all** — M, high impact
  - **Where:** `DashboardRootView.swift` sets `graphAutomationRuntime.isEnabled = (layoutMode == .canvas)`
    in `onAppear`, `onChange(of: layoutMode)` and `onChange(of: selectedTabIndex)`.
    `GraphDashboardView.activateGraphRuntime()` → `GraphDashboardRuntimeCoordinator.activate` calls
    `runtime.setEnabled(true)`. Both `GraphAutomationRuntime.handleTriggerFired` and
    `GraphDashboardView`'s `.onReceive(TriggerNodeNotifications.fired)` → `runActionsDownstream`
    execute actions.
  - **What goes wrong:** in Automation view, if the runtime ends up enabled, every trigger runs its
    actions twice (both executors). If it ends up disabled, triggers only the runtime generates
    (keystroke, time/wireless poll, PCO, ProPresenter, transcription, app state) never fire. Which
    one happens depends on SwiftUI's `onChange` ordering.
  - **Decision:** pick one executor for Automation view. Recommended: keep the runtime always
    enabled and the only executor, and make the Graph view's `onReceive(fired)` handle UI-only
    concerns (highlighting, run feedback) instead of executing. The alternative is keeping the
    Graph view as executor and gating `handleTriggerFired` (not trigger generation) while it's active.
  - **Check:** a keystroke trigger linked to a Notify action, fired in both views, produces exactly
    one notification each time.

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

- [ ] **The whole graph re-renders every few seconds with nothing changed** — M, investigated
  - **What's known:** `GraphDashboardView` re-runs its body about every 2–8 s at idle and 3–4
    times per gesture (~100–150 ms each, the remaining mid-gesture spikes), reported as
    `_tab changed` with the tab's value unchanged.
  - **Ruled out:** document writes. Logging every `tabs` write showed none during these
    re-renders (25 s of idle Automation, no writes).
  - **Cause:** `DashboardRootView.resolvedGraphTabBinding` builds a new `Binding(get:set:)`
    every time the root's body closure re-runs (which happens for many unrelated state
    changes). A new binding instance counts as a changed input, so the graph re-renders. An
    `Equatable` wrapper around the graph doesn't help: SwiftUI updates a stored `Binding`
    (a `DynamicProperty`) on its own, bypassing `==`.
  - **Fix options:** give the graph a stable binding (cache one per tab id in a reference held
    by the root) or a small `@Observable` tab model instead of a binding. Either needs care so
    the graph still updates when the tab changes elsewhere (canvas edits that add Button trigger
    nodes, PCO snapshots, runtime variable updates); verify those after the change.
  - **Done:** `scheduleTabsSaveDebounced` re-assigned every tab on each edit while reconciling
    Button trigger nodes; it now assigns only when a tab changed.
  - **Left as is:** `refreshPCOModulesForSelectedTab` rewrites PCO modules with an identical
    value on purpose ("bump the kind to itself to ensure SwiftUI sees a change") so PCO tiles
    redraw. It only runs on PCO events; replacing that with an explicit refresh signal is a
    separate change.

- [ ] **Remaining per-frame cost: native controls and accessibility** — L
  - With rebuilds gone, frame time is mostly native-control geometry (text fields, segmented
    pickers, steppers repositioned each frame) and accessibility updates (Logi Options+ and
    Raycast keep an accessibility client attached).
  - **Fix options:** click-to-edit fields (plain `Text` until focused), SwiftUI-drawn segmented
    controls in nodes, or a cached snapshot while a gesture is in progress.

- [ ] **Stall when crossing the compact-card threshold** — M
  - **Where:** `GraphDashboardView` (`shouldRenderDetailedGraphNode`, `GraphInteractionStore.isZoomedOut`).
  - **What goes wrong:** zooming in past ~65% builds every detailed node in the same frame.
  - **Fix:** stagger the swap over a few frames (nearest-to-center first), or keep detailed nodes
    built but hidden once they've been built in this session.
  - **Check:** hitch trace while zooming across the threshold.

## 2. High impact

- [ ] **Shure tiles redraw on every network packet** — M
  - **Where:** `ShureWirelessModule.swift`: `ShureWirelessService` writes `@Published` per packet
    (`lastHeardAt`, `micAudioLastUpdated`, `channelPresenceLastSeenAt`, `micAudioLevels`); tile
    holds it as `@StateObject` (~line 7904); `meterTick` timer in the view struct; unused
    `micLevelStats` (~7855).
  - **What goes wrong:** the `telemetrySnapshot` throttle (~2924) is bypassed, so each tile redraws
    at packet rate (~8 Hz per device or more), and the 10 Hz meter tick writes even while decaying
    to zero.
  - **Fix:** make per-packet bookkeeping non-published; tiles read only `telemetrySnapshot`; skip
    meter writes under ~0.001 change; delete `micLevelStats`; move the timer to a shared publisher.
  - **Check:** with a live Shure receiver, sample idle CPU and tile body counts before/after.

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

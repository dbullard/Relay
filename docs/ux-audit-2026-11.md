# Relay UI/UX Audit — November 2026

Scope: all SwiftUI view code under `Dashboard/` (~125 files, ~125k lines), macOS 26 + iPadOS 18.6.
Lenses: SwiftUI correctness/performance (swiftui-expert) and Apple HIG / *Designing Fluid Interfaces* (apple-design): feedback, interruptibility, spatial consistency, forgiveness, wayfinding, accessibility, reduced motion.
Method: 7 parallel code-reading audits by area, then spot verification. Items marked **✔ verified** were re-read and confirmed directly. Everything else was found by reading code; nothing was run. Items marked *(check at runtime)* depend on SwiftUI behavior that is best confirmed in the app.

---

## Status — 23 November 2026

All 15 top items and most of sections 3–4 are fixed in code (branches `fix/trust-items`, `feat/stale-display`, then `fix/live-mode-safety`, `feat/canvas-polish`, `feat/automation-safety`, `feat/module-polish`, `feat/settings-onboarding`). Both apps build and the covering unit tests pass. **None of it has been exercised in the running app yet.** The findings below are kept as written, for reference.

Still open:
- **Product decisions:** Shure Overview's severity-first sort (cards move when thresholds cross); renaming/merging the "External Connections / Integrations / External Devices / External Control" settings pages and splitting PCO setup across two of them; the spectrogram colour map (darkens toward its peak, no dB legend); the Access settings page being hidden on iPad.
- **Not done (larger work):** iPad pan momentum and zoom rubber-banding; a ghost snap target while dragging tiles; edge auto-scroll while wiring in the graph; manual device add inside the setup wizard; replacing the remaining `asyncAfter`/`Task.sleep` sequencing (the toolbar device-menu ones were left deliberately); a full sweep of the 233 fixed font sizes, hit targets and `.help`-only text outside the files touched.
- **Known existing bugs:** NDI "Retry Now" likely never appears (`NDIReceiver.runConnectionLoop` resets the retry count every attempt); one shared Resolume connection for all tiles, and its "active clips" include preview clips.
- **Behaviour changes to know about:** Show Guides moved to ⌘' and Auto-Hide Menu to ⌃⌘M; a double-tap no longer exits Live Mode; DAW record needs a second tap within 3s; countdowns show "OVER +m:ss" after zero; Live Mode asks before countdown/timer Reset and before any automation Test/Run/Fire; the Integrations settings page now saves as you go.

---

## 1. The short version

Relay's interaction foundations are better than most apps:
- Tiles and nodes track the pointer 1:1 and keep the grab offset.
- Pinch and trackpad zoom anchor under the cursor.
- The Live-chrome reveal uses `predictedEndTranslation` with springs.
- Every `glassEffect` is properly `#available`-gated.
- Most destructive canvas actions are undoable.
- `LiveModeRevealHandle` is a model control: a 44pt target, tap slop, honors Reduce Motion, and has an accessibility action.

The pitfalls cluster into five themes, roughly in order of how much they would hurt an operator mid-service:

1. **Trust: stale or failed state that looks live or successful.** The UI says "Saved", "Done", or shows a frozen meter/frame/slide when the underlying thing failed or disconnected.
2. **Cancel that doesn't cancel.** Several sheets bind straight to live state, so Cancel keeps the edits.
3. **Live-mode safety.** Accidental exits, modal interruptions, and unguarded hardware writes during a show.
4. **Accessibility is near-zero outside a few files.** Color-only status everywhere, icon-only buttons without labels, Reduce Motion and Reduce Transparency mostly ignored, small hit targets on iPad.
5. **Latency and fluidity seams.** Single-click delays from stacked double-tap gestures, `asyncAfter` sequencing, fixed-duration curves where springs belong, no haptics on snap.

---

## 2. Top 15 to fix first

| # | Sev | Issue | Where | |
|---|---|---|---|---|
| 1 | High | **Failed manual save still shows "Saved ✓".** The toolbar treats any `isSaving → false` as success. | `DashboardTopToolbarView.swift:2513`, `DashboardRootView.swift:8421` | ✔ verified |
| 2 | High | **Home (⌘⇧0) clears `hasUnsavedChanges`.** Opening a recent file or New from Home then skips the "Unsaved Dashboard" prompt and autosave, so edits are silently lost. | `RelayDashboardApp.swift:249` | ✔ verified |
| 3 | High | **Edit Device "Cancel" keeps the edits.** The editor is bound live to `store.devices`, and Save just closes the sheet. | `ExternalDevicesSettingsView.swift:465-483` | ✔ verified |
| 4 | High | **SPL calibration Cancel wipes the existing offset.** `startCapture()` applies 0 and nothing restores it. | `AudioInputsConfigView.swift:973-980, 908, 928` | ✔ verified |
| 5 | High | **ProPresenter "Add Profile" sheet edits the live connection's host, port, and password**, so Cancel doesn't revert. | `DashboardProPresenterSettingsView.swift:410-416` | |
| 6 | High | **Single-channel Shure tile never shows Offline/Reconnecting.** `recentReports` isn't cleared on disconnect, so frozen battery and frequency look live. | `ShureWirelessModule.swift:8834, 8471, 3713-3736` | |
| 7 | High | **A stale or muted Shure meter looks like silence.** An empty bar can mean a dead link, mute, or a quiet talker. | `ShureWirelessModule.swift:772, 808, 9828`, `ShureOverviewModule.swift:1121` | |
| 8 | High | **Countdown and timer drift.** They subtract per tick and skip ticks while *any* text field on the dashboard is active, while off-screen, or while the ticker is paused. | `TimeModuleView.swift:383-391, 422-427` | ✔ verified |
| 9 | High | **Button tile shows "Done" when the MIDI/OSC send failed** (the send result is discarded). | `ButtonModule.swift:1403-1420` | |
| 10 | High | **Toggling Live Mode rebuilds every tile.** An `if isLiveMode {…} else {…}` switches view identity, so webpages reload, NDI reconnects, and meters reset at the moment of going live. | `DashboardTileContainer.swift:1007-1012` | ✔ verified *(check at runtime)* |
| 11 | High | **Automation: Test/Run/Fire and console "Send/Clear" write to hardware with no guard in Live Mode.** Console Clear isn't undoable. | `GraphDashboardView.swift:2973`, `ConsoleGraphNodeView.swift:1243, 1274` | |
| 12 | High | **Automation: you can't delete a single wire.** The wires Canvas is `.allowsHitTesting(false)`; the only option is "Clear Links" on the whole node. | `GraphDashboardCanvasView.swift:383` | ✔ verified |
| 13 | High | **Automation: many actions fail silently.** OSC, HTTP, MIDI, Shure, and Sennheiser give no running/success/error feedback on the node. | `GraphDashboardView.swift:10241, 3869`, `GraphActionExecutor.swift:201, 607, 629` | |
| 14 | High | **iPad: no visible way to bring back hidden chrome.** `LiveModeRevealHandle` is macOS-only; iPad relies on an invisible top strip or a double-tap. | `DashboardRootView.swift:2949-2963` | |
| 15 | High | **Setup wizard has no exit after step 1.** There's no Close and Esc does nothing, so the only way out is to create a dashboard. | `OnboardingWizardView.swift:66-90` | |

---

## 3. Cross-cutting patterns

| Pattern | Approx. count | Representative locations | Fix direction |
|---|---|---|---|
| **Color-only status** (connected/offline, record, low battery, lock, over-limit, selected) | 30+ | `ProPresenterModule.swift:3313`, `DAWTransportModule.swift:2427`, `SennheiserWirelessModule.swift:1612`, `TimecodeModuleView.swift:114`, `DbReaderViews.swift:446`, settings status dots | Pair every color with a symbol change and/or a text word ("OFFLINE", "● REC", "LOW", "NO LOCK"). Copy the Shure Overview text pills. |
| **Stale data presented as live** | 8 modules | Shure single tile, Shure meter, ProPresenter slide, Timecode, NDI frame, PCO refresh, Resolume/YouTube (opposite failure: wipe on one failed poll) | One shared "stale" treatment: dim + badge + "Updated 12s ago". Keep last-good data and escalate to an error view only after N consecutive failures. The dB meter's existing stale overlay is the model. |
| **No accessibility modifiers at all** | ~40 of 125 files have zero | All of Modules/ except a handful | Icon buttons → `Label(…).labelStyle(.iconOnly)` + `.help`. Meters → `.accessibilityElement(children: .ignore)` + label/value. Toggles → `.isSelected` trait. |
| **Reduce Motion ignored** | 12 `repeatForever`, 2 checks app-wide | `DashboardTutorialOverlay.swift` (10), `ButtonModule.swift:1350`, `ShureOverviewHub.swift:443`, `DashboardFlipContainer.swift:96`, graph zoom-to-fit | Read `accessibilityReduceMotion` at the root; flip → crossfade, pulse → steady high-contrast border, camera moves → jump. |
| **Reduce Transparency never checked** | 0 checks; glass and materials in toolbar, add menu, tiles, rosters | `DashboardGlassSurface.swift`, `RosterTeamAssignmentsModule.swift` (stacked `.thinMaterial`) | Put the fallback in `DashboardGlassSurface` once: opaque fill + border when `accessibilityReduceTransparency` is on. |
| **Stacked `onTapGesture(count: 2)` + single tap** | ~6 | Tile select (`DashboardTileContainer.swift:1015`), canvas deselect (`DashboardRootView.swift:2005`), sidebar rows (reversed order, so the double-tap likely never fires: `DashboardTileOverviewSidebar.swift:574`), device rows | Select immediately via `.simultaneousGesture(TapGesture())`, and keep double-tap only for its secondary action. This removes the ~300ms lag on every click. |
| **Cancel without Esc / sheets without default action** | ~12 | ProPresenter, Resolume, Rosters, Tab settings, Group create, Pairing sheets, Add Node overlay | `.keyboardShortcut(.cancelAction)` on every Cancel/Deny/Close. |
| **Fields that commit per keystroke** | 4 | LAN port (clamps "5" → 1024), tile size fields (collapse to 44 while typing "300"), Webpage URL (reloads per keystroke), Text header (trims spaces as you type, so you can't type a space) | Use the existing `DeferredNumberField` / commit on `.onSubmit` + focus loss, with inline validation. |
| **Undo gaps** | ~6 | Duplicate tile, node drag-move, slider drags (flood the undo stack with full-document snapshots), console channel Clear, variable delete, PCO "Clear All Assignments", transcript Clear | Register one undo per gesture (`onEditingChanged` / drag start + end). Confirm only where truly irreversible. |
| **`.help()` as the only home for information** | ~15 | Button error text (`ButtonModule.swift:1063`), DAW status, settings status dots, inspector reset buttons | `.help` is invisible on iPad and to VoiceOver. Move critical info into a popover-on-tap or a visible label. |
| **Hit targets below 28pt (macOS) / 44pt (iPad)** | ~20 | Resize handles shrink with zoom (`DashboardResizeHandle.swift:546`), graph ports 26pt, tab close 18pt, selection toolbar scales with zoom, webpage toolbar (frame outside the button), RichText toolbar, inspector ↺ buttons | `.frame(minWidth:minHeight:)` + `.contentShape` inside the label; compute handle hit radius as `14 / zoom`. |
| **`asyncAfter` / `Task.sleep` sequencing on the input path** | 106 sleeps, 77 `asyncAfter` (many legit) | `RelayDashboardApp.swift:203-224`, `DashboardTopToolbarView.swift:454, 486`, `DashboardFlipContainer.swift:101`, `DashboardRootView.swift:2033` | Replace with `withAnimation { } completion:`, `.task(id:)`, or presentation callbacks. Each one adds 50–500ms of lag and race conditions. |
| **Fixed-duration curves where a spring belongs** | 83 `easeInOut(duration:)` vs 22 springs | Pill toolbar shows with a spring but hides with ease (`DashboardTopToolbarView.swift:295`); snap-on-release is unanimated | Default to `.spring(duration: 0.3, bounce: 0)`. Reserve bounce for things the user threw. |
| **Fixed `.font(.system(size:))`** | 233 | Most tile text scales from tile settings (intentional). The problems are chrome and labels at 7–10pt: RTA axes, roster rows, toolbar badges, launch cards. | Use text styles for chrome; set a floor (~11pt, ≥0.7 opacity) for scaled labels. |
| **`ForEach(… .indices)` on dynamic data** | 4 | `ActionGraphNodeView.swift:1526`, `TriggerGraphNodeView.swift:2260, 2486`, `DashboardTileContainer.swift:207` | `ForEach($items)` / stable IDs. Currently, row edit state sticks to the wrong row after reorder/delete. |

---

## 4. Findings by area

### 4.1 App shell, toolbar, Live Mode
- **[High]** Failed save shows "Saved ✓" (Top 15 #1) ✔
- **[High]** Home clears unsaved flag (#2) ✔
- **[High]** No visible reveal affordance on iPad (#14).
- **[High]** Main toolbar icon buttons (Live Mode, Settings, Rosters, Overview, Inspector, Add Tab) have no label or `.help`; on/off state is accent color only. `DashboardTopToolbarView.swift:2238-2359` (iPad variant ~2768-3125).
- **[Med]** Toolbar buttons show no hover/press state on macOS (`ToolbarIconChrome`, `:3398`). Use a `ButtonStyle` reading `isPressed` or `.glassEffect(.regular.interactive())`.
- **[Med]** Blocking modals over the live dashboard: "Connection Lost" alert (`DashboardRootView.swift:667`, `:1323`) and the pairing approval sheet (`:4901`). In Live Mode, use the existing banner and queue pairing requests.
- **[Med]** A stray double-tap on empty canvas exits Live Mode (`DashboardRootView.swift:1986`), and on any non-button tile (`DashboardTileCanvas.swift:200-216`).
- **[Med]** Deselect click lags by the double-click interval, plus a 0.25s `asyncAfter` (`DashboardRootView.swift:2005-2039`).
- **[Med]** Selection toolbar renders inside the zoomed layer, so it shrinks below 50% zoom; Distribute buttons are ~26×16pt (`SelectionActionToolbarView.swift:23, 98`).
- **[Med]** Tab close "x" is 18×18pt (`DashboardTopToolbarView.swift:1969`).
- **[Med]** Reduce Motion ignored by the 3D flip, pill/toolbar slides, and tab pulse.
- **[Low]** "Delete Tab" says "permanently" although it's undoable (`:2578`).
- **[Low]** A hidden toolbar Delete button bypasses the `shouldBlockDelete` guard the menu uses (`:2372`).
- **[Low]** Shortcut collisions: ⌥⌘M (Minimize All), ⌘; (Check Spelling) (`RelayCommands.swift:252, 255`). The shortcut reference sheet is incomplete.
- **[Low]** Pairing sheets have no Esc. Home can wait up to 4s behind the What's New fetch with no spinner (`RelayDashboardApp.swift:280-292`).

### 4.2 Canvas, tiles, inspector
- **[High]** Live Mode toggle rebuilds all tiles (#10) ✔ *(check at runtime)*
- **[High]** Tile select is delayed ~300ms by the stacked double-tap (`DashboardTileContainer.swift:1015-1023`).
- **[Med]** Selected/dragged tile draws *under* later tiles: the outer `.zIndex(1)` on each host (`DashboardTileCanvas.swift:182`) makes the inner 15/10 irrelevant among siblings ✔
- **[Med]** Sidebar double-click rename/edit likely never fires (single tap declared first) (`DashboardTileOverviewSidebar.swift:574-585, 479-484`). *(check at runtime)*
- **[Med]** Tile jumps unanimated on release when it grid-snaps (non-Shift) or is rejected by the overlap rule. Show a ghost target during drag, tint invalid drops, and settle with a critically damped spring.
- **[Med]** Group drag: the dragged tile snaps and checks overlap against members' *old* positions, so spacing drifts and the primary tile can bounce back alone (`DashboardTileContainer.swift:938-994`, `DashboardRootView.swift:6873`).
- **[Med]** No haptic on snap (iPad `.sensoryFeedback(.alignment, …)`, macOS `NSHapticFeedbackManager`).
- **[Med]** Resize hit halo is a fixed 14 canvas points, so it's 3.5pt at 25% zoom; iPad caps at 28pt (`DashboardResizeHandle.swift:546, 272`).
- **[Med]** Tile size fields resize on every keystroke (`DashboardTileEditView.swift:2657`, `DashboardInspectorPanelView.swift:641`).
- **[Med]** Slider drags push a full-document undo snapshot per change (`DashboardTileEditView.swift:2604` → `:3384`).
- **[Med]** Duplicate Tile isn't undoable (`DashboardTileContextMenu.swift:83-131`).
- **[Med]** VoiceOver can select/edit/delete tiles but can't move or resize them (`DashboardTileAccessibilityModifier.swift:77-86`). Add named actions that reuse `nudgeSelectedTiles`.
- **[Med]** Flip interrupted mid-flight: the first flip's `asyncAfter` completes during the second (`DashboardFlipContainer.swift:98-106`). Use `withAnimation {} completion:`.
- **[Low]** iPad two-finger pan has no momentum and zoom limits are a hard wall (no rubber-band) (`ViewportPanZoomModifier.swift:505-540`).
- **[Low]** iPad tap near a selected tile's edge registers an empty "Resize Tile" undo (`minimumDistance: 0`, `DashboardResizeHandle.swift:273`).
- **[Low]** 14 `Picker("")`/`ColorPicker("")` without labels; 6 ↺ reset buttons at caption2 size with `.help` only.
- **[Low]** Group sheet has no Esc; `DeferredNumberField` silently reverts invalid input; variable text fields can't be reached with Tab (`VariableSuggestionInputs.swift:510`).

### 4.3 Automation graph editor
- **[High]** No live-mode guard on Test/Run/Fire; console "Test" writes to the desk (#11).
- **[High]** Console Clear/Auto overwrite assignments; not undoable (data lives outside the graph undo) (`ConsoleGraphNodeView.swift:1274`).
- **[High]** Silent failures for most action kinds (#13).
- **[High]** No single-wire delete (#12) ✔
- **[High]** Keyboard/VoiceOver users can't connect nodes (ports are `DragGesture`-only). Add a "Connect to…" accessibility action or context menu using `receiverCandidateNodeIds(for:)`.
- **[High]** Rejected links give no reason; incompatible targets don't dim or turn red during a drag; `GraphLinkFailureReason` is never shown (`GraphDashboardView.swift:8193-8242, 8710`).
- **[Med]** Ports are 26pt with no hover/cursor feedback (`:6014-6039`).
- **[Med]** Node drag-moves aren't undoable (`:9867`).
- **[Med]** Missing ⌘A (function exists, never wired), arrow-key nudge, Esc on Add Node, Return-to-add in search; Delete/Duplicate are macOS-only.
- **[Med]** Empty-graph hint is non-interactive and doesn't mention double-click (`:5538`).
- **[Med]** All wires are the same white 2pt, so event and data flow are indistinguishable (`GraphDashboardCanvasView.swift:356`).
- **[Med]** No edge auto-scroll while dragging; below 0.55× nodes collapse, so you wire blind.
- **[Med]** Custom node controls use `.onTapGesture` without `.focusable()`, so Tab/Space can't operate them; collapse headers lack a button trait.
- **[Low]** Tiny steppers/checkboxes; OSC arg rows use `.indices` with unlabeled icon buttons; selection vs hover differs only by stroke opacity; zoom-to-fit ignores Reduce Motion; `minimumDistance: 1` makes click jitter dirty the document.

### 4.4 Wireless (Shure/Sennheiser) and Planning Center
- **[High]** Shure single tile never shows Offline (#6); stale/muted meter looks like silence (#7).
- **[High]** Sennheiser Spectera tiles flash "Connecting…" on every live-stream refresh, because `pollDevice` sets `.connecting` unconditionally (`SennheiserWirelessModule.swift:430-467`).
- **[Med]** Low battery: the icon is always `battery.100`, the value is small default-color text, and the alarm is a 35% red header tint that vanishes if the channel name is hidden. Sennheiser has no threshold at all.
- **[Med]** Sennheiser warnings show raw enum names ("lowBattery • audioClip") in grey caption text (`:1808`).
- **[Med]** Sennheiser connection states differ only by white opacity (10/7/6/6%).
- **[Med]** Overview alert border blinks at 1Hz forever with no Reduce Motion fallback (`ShureOverviewHub.swift:443`).
- **[Med]** Overview default sort is by severity, so cards jump position when thresholds cross and operators lose their spatial memory of "Pastor Mic" (`ShureOverviewModule.swift:52, 386`).
- **[Med]** PCO background refresh failures are swallowed; there's no "updated N min ago" and no "sign-in expired" state (`PCOTileView.swift:3914`).
- **[Med]** PCO team list scales to 58% (14pt → ~8pt), then clips with no "+N more" (`:3343`).
- **[Med]** Meters and RF bars are invisible to VoiceOver.
- **[Med]** PCO "Clear All Assignments" has no confirmation or undo (`PCOTeamAssignmentsModule.swift:1677`).
- **[Low]** White on system green "On" pill fails contrast; tiny unlabeled reset/remove buttons; Live Mode `onChange` spawns uncancelled `Task {}`s alongside `.task(id:)` (`PCOTileView.swift:2994`).
- *Done well:* the per-channel meter observation, the shared 30Hz clock, and the Overview's text pills.

### 4.5 Control modules (Button, ProPresenter, DAW, Transcription, Text)
- **[High]** Text tile header trims whitespace on every keystroke, so you can't type a space (`TextModuleModel.swift:429`).
- **[High]** Button tile shows "Done" when the send failed (#9).
- **[High]** Button error text lives only in `.help`, which is unreachable on iPad (`ButtonModule.swift:1055-1064`).
- **[Med]** ProPresenter keeps the old slide up as "Current" after an HTTP or decode error (`ProPresenterModule.swift:2141-2153, 3447`); its connection icon is color-only (`:3313`).
- **[Med]** DAW record state is color-only with no "REC" text and arms on a single tap; play state is tint-only; connection status is tooltip-only.
- **[Med]** Disabled Button tiles use `allowsHitTesting(false)` + 50% opacity: no `.disabled` and no reason shown. Icon-only Button tiles have no accessibility label or value.
- **[Med]** Transcript "Clear" sits next to Copy/Export with no confirm or undo (`LiveTranscriptionModule.swift:2671`).
- **[Med]** iOS rich-text toolbar edits bypass `undoManager`; its buttons are unlabeled, color-only, and 30–36pt (`RichTextToolbar_iOS.swift:236-455`).
- **[Low]** Font size steps 1pt per tap; "Done" isn't actually pinned; macOS B/I/U don't show state; long transcription errors overflow; no "Listening…" empty state; ProPresenter decodes `@AppStorage` JSON and builds a `DateFormatter` in `body` on every poll.

### 4.6 Other modules (Time, Timecode, NDI, Webpage, Resolume, YouTube, Rosters, RTA, Spectrograph, dB)
- **[High]** Countdown/timer drift (#8) ✔. Countdown also stops dead at 0:00 with no overrun or "OVER" state.
- **[Med]** Timecode lock loss = red text on a frozen value.
- **[Med]** NDI: the status appears three times and the material card covers "Retry Now"; there's no stale-frame badge even though `lastFrameDate` exists.
- **[Med]** Resolume/YouTube replace content with "Error:" after one failed poll; Resolume `connect()` on every appear flashes "Connecting…"; one shared singleton for all Resolume tiles (and it's held as `@StateObject`).
- **[Med]** Resolume "active clips" includes preview/selected clips.
- **[Med]** Webpage URL field reloads per keystroke; no loading or error state; toolbar hit area is only the 15pt glyph and unlabeled.
- **[Med]** Roster Picker reads a stale roster copy; the "Show row number" toggle does nothing (`RosterPickerModule.swift:14-21, 42, 314`).
- **[Med]** Roster Team Assignments uses fixed 10–15pt text, clips without scrolling, and stacks three materials per row.
- **[Med]** RTA/Spectrograph labels are 7–9pt at 35–60% white; the RTA legend toggle is an `onTapGesture` chip.
- **[Low]** The spectrogram's default color map darkens toward its peak (loud reads quieter) and has no dB legend; a missing document/image looks like "never configured"; countdown Reset is one tap in live mode; PCO Live web view leaves swipe-back enabled when scroll is disabled.

### 4.7 Settings, onboarding, launch
- **[High]** Edit Device Cancel keeps edits (#3) ✔; calibration Cancel wipes offset (#4) ✔; ProPresenter Add Profile edits live config (#5); wizard has no exit (#15).
- **[Med]** Wizard `minHeight: 820` likely clips in iPad sheets; use `.presentationSizing(.page)` or scroll.
- **[Med]** First-run device list says "No devices match your search" with no search typed. Use `ContentUnavailableView` with Add/Scan.
- **[Med]** "Import and Restart" calls `exit(0)` without checking unsaved changes (`PreviousRelayImporter.swift:133`).
- **[Med]** iPad "Set as Startup File" is advertised but compiled out (`RelayLaunchScreenView.swift:436`).
- **[Med]** Settings is a modal sheet over the live dashboard; the section names "External Connections / Integrations / External Devices / External Control" are confusing, and PCO setup is split across two of them.
- **[Med]** The Integrations page alone requires Save and loses edits on navigation; it shows "Configured" before saving.
- **[Med]** ~10 hard-coded white fills vanish in Light appearance (`DashboardAccessSettingsView.swift:79`, `DashboardSettingsView.swift:353`, `MIDISettingsView.swift:252`).
- **[Med]** Denied mic/speech permission has no "Open Settings" path; the Access page is hidden on iPad.
- **[Med]** Variable delete is instant (tiles reference variables by name), while Copy pops a modal: friction is backwards.
- **[Med]** Scan sheet's primary button is a disabled "Done"; the wizard Devices step has no Rescan or manual add.
- **[Low]** Wizard checklist rows don't expose checked state; launch-screen remove "x" is 9pt; "No recent files" offers no action.

---

## 5. Suggested sequencing

1. **Trust and data-loss fixes (small, high value).** Save result plumbing (#1), the Home flag (#2), the draft-copy pattern for the three Cancel sheets (#3–5), date-based countdown (#8), real send results for Button tiles (#9), the Text header trim (4.5), and the Live Mode view identity fix (#10).
2. **A shared "connection/stale state" component** (dim + badge + age + text label), adopted by Shure, Sennheiser, ProPresenter, Timecode, NDI, PCO, Resolume, and YouTube. This one component retires most of themes 1 and 4's color-only issues.
3. **Live Mode safety pass.** Remove double-tap exit, demote modals to banners, guard hardware-writing automation buttons, and bring the reveal handle to iPad.
4. **Accessibility baseline.** Root-level Reduce Motion handling, a Reduce Transparency fallback in `DashboardGlassSurface`, labels on icon buttons, `.cancelAction` everywhere, hit-target minimums, and VoiceOver actions for tile move/resize and node connect.
5. **Fluidity polish.** Fix gesture ordering for instant select, replace `asyncAfter` sequencing, add snap haptics, show a ghost snap target with a spring settle, add pan momentum and zoom rubber-banding on iPad, and make wires selectable.

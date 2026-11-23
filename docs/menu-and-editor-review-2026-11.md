# Menus and Tile Editor Review — November 2026

Scope: the macOS menu bar (`RelayCommands.swift`), the iPad "more" menus, the toolbar, every context menu, the Live Mode menu, and the tile editor (inspector). I read the code on branch `audit/remaining` and judged it against the macOS/iPadOS Human Interface Guidelines. Nothing was run, so look at the proposed structures in the app before committing to them.

## Status — 23 November 2026

The fixes that needed no decision are done on `audit/remaining` (branches `feat/menu-cleanup` and `feat/editor-cleanup`):
- **Menu bar:** File reordered; an Arrange *submenu* inside Edit (not a new top-level menu); View toggles for Tile Overview, Inspector and Show Grid; zoom commands; Window menu items; Tabs menu items.
- **Context menus:** reordered with count labels; a new empty-canvas menu.
- **Sidebar:** Edit and Delete added, "pt" units, and Bring Forward / Send Backward (list order is stacking order).
- **Tile editor:** undo for every module, the header names the tile, disabled-state captions, one title vocabulary, iPad parity, and the panel width fix.

Both apps build and the covering tests pass. Nothing has been tried in the running app yet. The decisions in section 5 are still open; nothing in them was implemented.

---

**Summary.** The commands exist, but they're scattered. The same action has different names in different places, and several actions are reachable from only one place (usually a context menu or a sidebar row) that people won't find. The tile editor is in good shape: one inspector, two tabs, changes apply live. But it splits tile-wide settings across three surfaces, and a dozen module types change settings without undo.

---

## 1. What exists today

### macOS menu bar

| Menu | Items (shortcut) |
|---|---|
| Relay | Settings… (⌘,), Check for Updates…, Quit Relay (⌘Q) |
| File | Home / Close Home (⇧⌘0) · New Dashboard (⌘N) · Setup Wizard… · Open Dashboard… (⌘O) · Open Recent ▸ · Save Dashboard (⌘S) · Save Dashboard As… (⇧⌘S) |
| Edit (after text editing) | Duplicate Tile/Node (⌘D) · Group Selected Tiles… (⌘G) · Resize Dashboard Canvas… · Bring All Tiles Into Canvas · Delete Selected Tiles (⌫) · Hide/Show Selected (⇧⌘H) |
| View (after Sidebar) | Canvas View (⌘1) · Automation View (⌘2) · Variables (⌥⌘V) · Snap to Grid (⌥⌘G) · Live Mode (⌘L) · Show Guides (⌘') · Auto-Hide Menu (⌃⌘M) · Show System Status |
| Tabs | New Tab (⌘T) · Select Previous/Next Tab (⌘[ / ⌘]) · Select First/Last Tab (⌥⌘[ / ⌥⌘]) |
| Help | Relay Help Center · Start Tutorial… · Keyboard Shortcuts… · Export Logs… |

### Other surfaces

- **Toolbar (macOS):** tab strip and New Tab on the left, Undo/Redo, then Live Mode, Tab Settings, Rosters, Canvas/Automation toggle, Settings and Inspector on the right. The Tile Overview toggle is also here.
- **iPad "more" (…) menu:** there are two implementations, a native `Menu` and a custom row list with File/Edit/View headers. Between them they repeat New, Setup Wizard, Open, Save, Save As, Duplicate, Group, Hide/Show, Resize Canvas, Bring All Tiles In, Auto-hide Toolbar, Live Mode, Snap to Grid, Show Grid and Show Guides.
- **Tile context menu:** Edit Tile(s)… · Group Tile(s)… · — · Duplicate Tile (disabled when several tiles are selected) · — · Tidy Up Horizontally / Vertically (disabled with fewer than 2 tiles) · Align Selected Tiles to Grid (only when snapping is on) · Resolve Tile Overlaps · Delete Tile(s).
- **Tab context menu:** Rename Tab · Duplicate Tab · **Delete Tab** · — · Canvas Size… · — · sync items (Reconnect / Disconnect / Make Synced Tab / Stop Syncing).
- **Tile Overview sidebar row:** Rename Tile · — · Edit Size(s)… · — · Hide/Show Tile · — · Move Up · Move Down. **Group row:** Edit Group · — · Delete Group.
- **Guide:** Edit Guide · Delete Guide.
- **Live Mode menu:** Previous/Next Tab, tab picker, Canvas/Automation toggle, and a "more" menu with Tab Settings, Rosters and Settings.
- **Empty canvas:** no context menu; that code is commented out in `DashboardRootView`.
- **Keyboard only, not in any menu:** Select All (⌘A on the canvas); arrow-key nudge.

---

## 2. Problems

### Menu bar
1. **Edit holds canvas and layout commands that aren't edits.** Resize Dashboard Canvas…, Bring All Tiles Into Canvas, and (on iPad) Snap/Grid/Guides belong in a layout menu. Meanwhile the arrange commands people look for (Tidy Up, Align to Grid, Resolve Overlaps, Distribute) are only in the tile context menu and the selection toolbar.
2. **One action, several names.**
   - "Resize Dashboard Canvas…" (Edit), "Canvas Size…" (tab menu) and "Change dashboard size" are the same thing.
   - ~~"Tidy Up" and "Distribute" are the same thing.~~ *Correction:* they're different. Tidy Up packs tiles edge to edge and keeps their sizes; Distribute resizes them into a grid that fills the canvas. Both names stay.
   - "Auto-Hide Menu" (macOS) and "Auto-hide Toolbar" (iPad) are the same thing; the macOS name is wrong, since the item hides the toolbar, not a menu.
   - "Edit Size…" (sidebar, in px) and the inspector's W×H (in pt) edit the same value with different units.
3. **Mode-dependent titles don't always switch.** Duplicate becomes "Duplicate Node" in Automation view, but "Delete Selected Tiles" and "Group Selected Tiles…" stay tile-worded and stay enabled there.
4. **Canvas View / Automation View draw their own checkmarks** with an `HStack` and a clear spacer, so they don't line up with system checkmarks. A `Picker` with `.pickerStyle(.inline)` in the View menu gives native checkmarks.
5. **Tab shortcuts break convention.** On macOS ⌘[ and ⌘] mean Back/Forward. Safari, Finder, Xcode and Terminal switch tabs with ⇧⌘[ / ⇧⌘] and ⌃Tab / ⌃⇧Tab.
6. **Gaps.**
   - Edit has no Select All, Deselect, Copy/Paste or Ungroup.
   - View has no zoom commands (Zoom In ⌘+, Zoom Out ⌘−, Actual Size ⌘0, Zoom to Fit), even though the canvas zoom popover already has Actual Size.
   - View has no Inspector or Tile Overview toggle (the HIG convention is ⌥⌘I and ⌃⌘S).
   - macOS has no **Show Grid** toggle at all; only iPad can turn the grid off.
   - Tab Settings, Rename/Duplicate/Delete Tab, Rosters and "Import from Previous Relay…" have no menu item.
   - Nothing opens the inspector from the keyboard.
7. **Variables is a window, but it sits in View.** It belongs in the Window menu, next to the other floating panels (Rosters).
8. **Setup Wizard… sits between New and Open.** That breaks the familiar New / Open / Open Recent group. It reads better as "New from Setup Wizard…" right under New Dashboard.

### Context menus
9. **The empty canvas has no context menu.** Right-clicking the background is where Mac users expect Add Tile, Paste, Select All, the grid/guide toggles and Canvas Size.
10. **Delete Tab sits in the middle of the tab menu**, above Canvas Size and the sync items. Destructive items go last, after a divider.
11. **"(s)" labels** ("Edit Tile(s)…", "Group Tile(s)…", "Delete Tile(s)") read as unfinished. Use the count: "Edit 3 Tiles…", "Delete 3 Tiles".
12. **Group Tile(s)… shows for a single tile**, where grouping makes no sense, and Duplicate is disabled for a multi-selection even though ⌘D duplicates.
13. **Each surface covers a different part of tile management.** Rename, Hide and Move Up/Down are only in the sidebar row. Duplicate, Tidy Up and Delete are only in the tile menu. Edit Tile isn't in the sidebar row, and Delete Tile isn't there either.
14. **"Move Up / Move Down" in the sidebar is unclear.** It reorders the list (and the drawing order?), but the label doesn't say which. "Bring Forward / Send Backward" is the standard wording if it changes stacking order.

### Toolbar
15. **App-level and dashboard-level buttons are mixed together.** Settings (app-wide, already ⌘, and in the Relay menu) sits between document tools. Rosters is a top-level button although it's a reference panel used occasionally.
16. **Tab Settings is both a toolbar button and absent from the tab's own menu.** People who right-click a tab won't find it.

### Tile editor (inspector)
17. **The header says "Edit Tile" but never names the tile** or says how many are selected. Rename is only possible in the sidebar.
18. **Tile-wide settings are split across three places:**
    - **Formatting tab:** background, size, padding, text.
    - **Modules tab:** module list. Module Layout (Vertical/Horizontal) is in Formatting even though it arranges the modules listed in the Modules tab.
    - **Sidebar:** name, visibility, order, and a second size editor.
19. **The Modules tab is one long column.** The module list, the selected module's settings, then "Module Spacing" at the very bottom. Button and Planning Center settings run several screens, and the spacing card is easy to miss.
20. **Duplicated concepts with near-identical names:**
    - Padding appears as tile "Module Padding", per-module "Top/Bottom padding" and Button "Horizontal/Vertical Padding".
    - Corner radius and text colour/size are set both on the tile and inside modules.
    - Header naming varies: "Show header", "Show header (Planning Center)", "Show module title", "Show title", "Header background", "Show header background", plus the tile's "Show tile name".
21. **Undo is inconsistent.**
    - Formatting coalesces drags into one step.
    - Text, Image, Webpage, Button, PCO, Time and Shure settings add one undo step per keystroke.
    - Person, Roster Team Assignments, Shure Overview, Sennheiser, ProPresenter, Resolume, SPL Meter, RTA, Spectrograph and Live Transcription settings, and sidebar reorder/hide, are not undoable at all.
22. **Disabled with no reason given:** the toolbar Inspector button when nothing is selected, Background Color while a gradient is on, and module Duplicate/Delete until a module is selected.
23. **Platform gaps:**
    - Section help buttons exist only on iPad, and the Module Spacing one does nothing.
    - Module drag-to-reorder is macOS only.
    - iPad has two Close buttons.
    - iPad opens on a "Select a Module" placeholder, while macOS shows the first module.
24. **The Shure "Show module title" toggle does nothing.** It starts as `true` every time, and no caller supplies its save callback. The Shure tile's title actually follows the tile's "Show tile name". Remove the toggle.
25. **The macOS editor asks for `minWidth: 420` inside a 380pt panel** (`DashboardTileEditView.swift:1754`, `DashboardRootView.swift:79`). Check in the app whether it clips or overflows.
26. **Unclear labels:** single-letter "W"/"H"; the icon-only alignment segments use `distribute.*` symbols; Delete sits right next to Duplicate under the module list.

---

## 3. Proposed menu bar

Ordered by how often each item is used, with related items grouped and destructive items last. ★ marks new items; ↪ marks items moved from elsewhere.

**Relay**
- About Relay · Check for Updates…
- Settings… ⌘,
- ↪ Import from Previous Relay…
- Services · Hide/Show · Quit ⌘Q

**File**
- New Dashboard ⌘N
- ↪ New from Setup Wizard… (renamed from "Setup Wizard…")
- Open… ⌘O
- Open Recent ▸
- —
- Home ⇧⌘0
- —
- Close ⌘W (system)
- Save ⌘S
- Save As… ⇧⌘S

**Edit**
- Undo / Redo (system)
- —
- ★ Cut ⌘X · ★ Copy ⌘C · ★ Paste ⌘V (tiles and nodes; skip for now if copy/paste is out of scope)
- Duplicate ⌘D
- Delete ⌫ (title follows the mode: "Delete Tiles" / "Delete Nodes")
- —
- ★ Select All ⌘A (already works from the keyboard)
- ★ Deselect All ⇧⌘A
- —
- ★ Edit Tile… ⌘E (opens the inspector on the selection)
- Group… ⌘G
- ★ Ungroup ⇧⌘G
- —
- Hide Selected ⇧⌘H
- ★ Show All Hidden ⌥⇧⌘H

**Arrange** ★ (new menu; replaces the canvas items in Edit and the context-menu-only arrange items)
- ★ Add Tile ⌥⌘N
- ★ Add Guide ▸ (Horizontal / Vertical)
- —
- ↪ Distribute Horizontally (renamed from "Tidy Up Horizontally")
- ↪ Distribute Vertically
- ↪ Align to Grid
- ↪ Resolve Overlaps
- —
- ↪ Snap to Grid ⌥⌘G
- ★ Show Grid (macOS currently can't turn the grid off)
- Show Guides ⌘'
- —
- ↪ Canvas Size… (one name everywhere)
- ↪ Bring All Tiles Into View

**View**
- Canvas ⌘1 / Automation ⌘2 (native picker checkmarks)
- —
- ★ Show/Hide Tile Overview ⌃⌘S
- ★ Show/Hide Inspector ⌥⌘I
- —
- ★ Zoom In ⌘+ · ★ Zoom Out ⌘− · ★ Actual Size ⌘0 · ★ Zoom to Fit ⌘9
- —
- Auto-Hide Toolbar ⌃⌘M (renamed from "Auto-Hide Menu")
- Show System Status
- —
- Live Mode ⌘L
- Enter Full Screen (system)

**Tabs**
- New Tab ⌘T
- ★ Duplicate Tab
- ★ Rename Tab…
- ★ Tab Settings…
- —
- Show Previous Tab ⇧⌘[ and ⌃⇧Tab (changed from ⌘[)
- Show Next Tab ⇧⌘] and ⌃Tab (changed from ⌘])
- Show First Tab · Show Last Tab
- —
- ★ Sync ▸ (Make Synced Tab / Stop Syncing / Reconnect)
- —
- ★ Delete Tab…

**Window**
- Minimize · Zoom (system)
- —
- ↪ Variables ⌥⌘V
- ★ Rosters ⌥⌘R
- —
- Bring All to Front (system)

**Help**
- Relay Help ⌘? (system search field)
- Keyboard Shortcuts…
- Start Tutorial…
- —
- Export Logs…

**iPad.** Merge the two "more" menus into one native `Menu` that mirrors the File / Edit / Arrange / View groups above, as sections. iPadOS 26 also shows `Commands` in its own menu bar, so on 26 the "more" menu can shrink to the items people use by touch.

### Proposed context menus

**Empty canvas** ★ (new)
- Add Tile
- Paste (if added)
- Select All
- —
- Show Grid · Snap to Grid · Show Guides
- —
- Add Guide ▸
- Canvas Size…

**Tile** (one or more selected)
- Edit Tile… / Edit 3 Tiles…
- Rename… (single tile only)
- —
- Duplicate (also for a multi-selection)
- Group 3 Tiles… (only with 2 or more) / Ungroup (on a group)
- Hide
- —
- Arrange ▸ (Distribute Horizontally, Distribute Vertically, Align to Grid, Resolve Overlaps); only with 2 or more tiles, or Align to Grid for one
- —
- Delete / Delete 3 Tiles

**Tab**
- Rename Tab… · Duplicate Tab · Tab Settings… · Canvas Size…
- —
- Sync items
- —
- Delete Tab…

**Sidebar tile row**
- Edit Tile… · Rename… · Edit Size…
- —
- Hide · Bring Forward · Send Backward (or "Move Up / Move Down in List" if it only reorders the list)
- —
- Delete

### Proposed toolbar (macOS)

From left to right:
- Tile Overview
- tab strip and New Tab
- Undo/Redo
- *(flexible space)*
- Canvas | Automation (segmented)
- Live Mode
- *(space)*
- Inspector (trailing edge, per HIG)

Settings and Rosters leave the default toolbar for the Relay menu and the Window menu. If you rely on them mid-show, keep them as optional items through **Customize Toolbar…** rather than removing them. Tab Settings goes to the tab context menu and the Tabs menu. iPad keeps a gear because iPadOS 18 has no menu bar.

---

## 4. Proposed tile editor changes

1. **Header names the selection:** "Stage Left Mic" or "3 Tiles", with the name editable inline. That makes Rename reachable in the inspector, and the sidebar keeps its own Rename.
2. **Three tabs in the order people work: Modules · Layout · Style.**
   - **Modules:** the module list only, plus Add Module.
   - **Layout:** tile Size (Width/Height, spelled out), Module Layout (moved from Formatting), Module Padding, and the selected module's Height / Top / Bottom spacing.
   - **Style:** background/gradient, opacity, corner radius, Show tile name, text formatting.
3. **Selected module settings get their own level.** Choosing a module pushes its settings with a back chevron (a NavigationStack inside the panel), instead of stacking them under the list. That solves the long scroll and makes Module Spacing findable.
4. **One header vocabulary:** "Show title" for every module that has one, and "Title background" for its fill. Keep "Show tile name" for the tile itself, and remove the Shure duplicate (finding 24).
5. **Undo for every module.** Route the ten modules that write straight to the tab through the same coalescing undo path as Formatting, and coalesce the keystroke-level ones the same way. Add undo for sidebar hide/reorder.
6. **Show why something is disabled:**
   - "Select a tile to inspect" when nothing is selected.
   - "Turn off gradient to pick a single colour."
   - Move module Delete away from Duplicate (put it in the row's context menu and swipe action only).
7. **Platform parity:** help popovers on macOS too (or drop them on both); module drag-reorder on iPad; one Close button on iPad; same first-module default on both.
8. **Units:** "pt" everywhere (the sidebar says "px").

---

## 5. Decisions needed

Carried over from the audit's open list, plus the new ones from this review:

1. **Shure Overview sort:** keep severity-first (cards move when a channel goes into alarm) or default to a fixed channel order with alarm highlighting?
2. **Settings pages:** merge "External Connections / Integrations / External Devices / External Control" into, for example, **Connections** (devices you talk to) and **Accounts** (Planning Center, YouTube, cloud services), and put PCO setup on one page?
3. **Spectrogram colour map:** switch to a perceptually uniform map that gets brighter with level, and add a dB legend?
4. **Access settings on iPad:** expose them there or not?
5. **The new Arrange menu** versus keeping layout items in Edit and View.
6. **Toolbar:** move Settings and Rosters out of the default toolbar?
7. **Tab shortcuts:** change to ⇧⌘[ / ⇧⌘]? This changes muscle memory for existing users.
8. **Copy/Paste of tiles and nodes:** in scope now, or later?
9. **Inspector tabs:** restructure into Modules · Layout · Style with drill-in module settings (the largest change here)?

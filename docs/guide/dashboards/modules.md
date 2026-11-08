# Modules: add live data and controls to Relay tiles

Modules are the content blocks inside Relay tiles. Learn what they do and how to choose the right ones.

Modules are what give tiles meaning. Each module either displays information, pulls in live data, or provides a control you use during an event.

## Adding a module

1. Select a tile.
2. Open the add-module menu.
3. Choose a module.
4. Configure it in the inspector.

You can add more than one module to the same tile when the content belongs together visually.

## Common module groups

### People and planning

- Planning Center
- PCO Team Assignments
- Roster Team Assignments
- Person

### Wireless

- Shure Overview
- Shure
- Sennheiser in Preview mode or Debug builds

### Audio

- SPL Meter
- Live Transcription
- DAW Transport
- Real-Time Analyzer (RTA)
- Spectrograph

### Video and presentation

- ProPresenter
- NDI Feed

### Utility

- Text
- Image
- Picker
- Document
- Webpage
- Time
- Timecode
- Separator
- Button

## Preview modules

Some modules are Preview-only and should be evaluated separately from the main feature set. Turn Preview on under `Relay > Settings` → **Preview**; see [Preview features](../app/preview-features.md).

- YouTube Live Stream Monitor (Debug builds only) and NDI Feed are Preview
- Sennheiser appears only in Preview mode or Debug builds
- Shure Overview, the multi-device wireless summary module, appears only in Preview mode or Debug builds

The standalone Shure module and Live Transcription are stable and not Preview-gated.

## Choosing one tile vs. multiple tiles

Use one tile when modules belong together visually. Use separate tiles when content should move, resize, or scale independently on the canvas.

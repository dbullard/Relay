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

- Shure Overview (Preview)
- Shure
- Sennheiser

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

## Availability and badges

Not every module is available in every build. Three things can apply:

- **Preview:** **Shure Overview** and the **YouTube Live Stream Monitor** need Preview on; the YouTube monitor also needs your own Google OAuth client.
- **Preview features:** Some related settings and device models appear only when Preview is on under `Relay > Settings` → **Preview**. See [Preview features](../app/preview-features.md).
- **Beta badge:** **Sennheiser** and **NDI Feed** are available in every build but carry a beta badge in the module picker. Test them on your own network before relying on them live.

The standalone **Shure** module and **Live Transcription** are stable, with no badge.

## Choosing one tile vs. multiple tiles

Use one tile when modules belong together visually. Use separate tiles when content should move, resize, or scale independently on the canvas.

# NDI video: monitor NDI sources in Relay

Capture NDI sources on your network for low-latency video monitoring on your dashboard.

> [!WARNING]
> The NDI Feed module carries a beta badge. It is available in all builds, but needs the separately installed NDI runtime (see [NDI runtime](../../DEVELOPMENT.md#ndi-runtime)). Test it on your production network before you rely on it in a live show.

The NDI Feed module brings low-latency video monitoring to your dashboard by capturing NDI® sources on your network.

## Setup
1. Ensure your Mac is on the same local network as your NDI sources.
2. Add the **NDI Feed** module to a tile.
3. In the inspector, pick a source from the auto-discovered **NDI® Source** list. If your source isn't listed, open "Can't find your source?" for a reminder to check that the sending device is on the same network subnet.

## Settings

The module's inspector is organized into four groups:

- **Video** — a Quality control (**Poster** · **Preview** · **Live**) that trades frame rate for CPU and bandwidth: Poster runs at 1 fps for minimal impact, Preview at 15 fps for general monitoring, and Live at 30 fps for full quality. A Scale control (**Fit** · **Fill**) and a **Show overlay** toggle are also here.
- **Network** — a Network Interface picker (**Auto**, **Global Preferred**, or a specific NIC) for routing NDI traffic over a particular network adapter, plus **Prefer low latency** and **Allow NIC fallback** toggles.
- **Audio** — collapsed by default. **Enable audio**, and a **Mute in tile** toggle that appears once audio is on.
- **Source** — the source picker described above.

## Limits and reliability

- Relay allows **up to 2 active NDI modules per tab**. A third module on the same tab shows as disabled in the module catalog with an inline "Limit reached" note — add it to a different tab instead, or remove an existing NDI module first.
- If a source stops responding, Relay retries automatically with a short "Reconnecting…" badge in the tile corner. If reconnection keeps failing after a few attempts, the tile shows a clear error with a **Retry Now** button rather than a raw connection error.
- **Beta warning:** Always validate performance on your actual production network — high NDI traffic can affect Wi-Fi stability, especially with multiple Live-quality streams active at once.

> [!NOTE]
> NDI® is a registered trademark of Vizrt NDI AB. Learn more at [ndi.video](https://ndi.video).

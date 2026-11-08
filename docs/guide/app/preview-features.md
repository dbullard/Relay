# Preview features: try newer, still-evolving capabilities

Preview features are early or evolving parts of Relay that are available for testing before they are considered stable for every show.

> [!WARNING]
> Don't assume a Preview feature is ready for a mission-critical show just because it appears in the app. Test it in your own workflow first.

## Turn Preview on

1. Open `Relay > Settings` and choose **Preview**.
2. Turn on **Enable preview features**.
3. Quit and reopen Relay. The setting takes effect after a restart.

Preview is off until you turn it on. Debug and release builds behave the same.

## What Preview includes

These need **Preview**:

- **[Smart Lights](../integrations/lighting.md)**: the Smart Light Control action node
- **ProPresenter State trigger**: the [automation trigger](../dashboards/nodes/triggers.md#propresenter-state-beta) that fires when the slide, presentation, message, or timer changes
- **Extra DAW transport protocols**: Logic Pro HUI, Reaper HUI and MCU, Cubase/Nuendo HUI, Digital Performer HUI, and Generic MTC/MMC. Pro Tools HUI and Generic HUI are always available. See [DAW Transport](../dashboards/modules/audio-visual.md).
- **Newer device models**: Shure `ANX4`, `ADTD`, and `ADTQ` ([wireless devices](../integrations/wireless-devices.md)), the Allen & Heath dLive, Avantis, and SQ, Behringer WING, Avid VENUE S6L, and Yamaha DM7, RIVAGE PM, and CL/QL consoles ([audio consoles](../integrations/audio-consoles.md))
- **[Shure Overview](../dashboards/modules/wireless.md#shure-overview)** module and the **[YouTube Live Stream Monitor](../integrations/youtube-live.md)**, which also needs your own Google OAuth client. See [Integrations that need your own credentials](../../INTEGRATIONS.md#youtube-stream-monitor)
- **Wireless diagnostics logging** controls (see below)

## Other labels you'll see

Not everything marked beta needs Preview:

- **Beta badge, available everywhere:** [Sennheiser](../dashboards/modules/wireless.md#sennheiser), [NDI Feed](../integrations/ndi.md), [Vista](../integrations/vista.md), the **If / Else** node, and the Allen & Heath Qu console. They carry a badge in the app but appear in every build.

The standalone **Shure** module and **Live Transcription** are stable.

## Preview tools in Settings

With Preview on, the **Preview** settings page also shows **Wireless Diagnostics Logging**: verbose logging toggles for Shure and Sennheiser device families, each with a reset-to-defaults button. Verbose tracing is only active when Preview is on, after you restart Relay.

## When to use Preview features

Preview features are a good fit when you want early access to a capability that is still being refined, you can test it ahead of a live event, and you're comfortable reporting problems.

Avoid relying on one for the first time during a live show. Roll them out one at a time: one Preview variable is much easier to evaluate than a whole chain of new behavior.

## Troubleshooting

### A Preview feature behaves inconsistently

Check that Preview is on and that you restarted Relay after turning it on. Then check whether the feature depends on another connection, permission, or service, and whether the behavior repeats on demand or only occasionally.

### A Preview feature is missing entirely

- Confirm **Enable preview features** is on under `Relay > Settings` → **Preview**, and restart Relay.
- Some device models only appear when the required hardware or integration is present.
- The YouTube Live Stream Monitor needs Preview and your own OAuth client.

### I found a problem

[Open an issue](https://github.com/dbullard/Relay/issues/new/choose) with what you expected, what happened, exact reproduction steps, whether it happens every time, and any screenshots or diagnostics. Use synthetic data and don't post private addresses or customer information.

# Preview features: try newer, still-evolving capabilities

Preview features are early or evolving parts of Relay that are available for testing before they are considered stable for every show.

> [!WARNING]
> Don't assume a Preview feature is ready for a mission-critical show just because it appears in the app. Test it in your own workflow first.

## Turn Preview on

1. Open `Relay > Settings` and choose **Preview**.
2. Turn on **Enable preview features**.
3. Quit and reopen Relay. The setting takes effect after a restart.

Debug builds (the `Relay (DEBUG)` scheme in Xcode) always have Preview on. Release builds have it off until you turn it on.

## What Preview includes

The Settings page describes Preview as including newer automation triggers, smart lights, extra DAW protocols, and newer device models. In the docs, these areas are marked `Preview`:

- **[Smart Lights](../integrations/lighting.md)** and **[Vista](../integrations/vista.md)** automation destinations
- **[Sennheiser](../integrations/wireless-devices.md)** wireless devices and module
- **[Shure Overview](../dashboards/modules/wireless.md#shure-overview-preview)**, the multi-device wireless summary module
- Newer device models, such as some Shure models and certain audio console models, which show a badge in External Devices
- Extra DAW transport protocols
- Newer automation triggers

The standalone **Shure** module and **Live Transcription** are stable and are not Preview.

> [!NOTE]
> The **YouTube Live Stream Monitor** is limited to Debug builds and needs your own Google OAuth client. See [Integrations that need your own credentials](../../INTEGRATIONS.md#youtube-stream-monitor).

## Preview tools in Settings

With Preview on, the **Preview** settings page also shows **Wireless Diagnostics Logging**: verbose logging toggles for Shure and Sennheiser device families, each with a reset-to-defaults button. Verbose tracing is only active when Preview is on (or in Debug builds), after you restart Relay.

## When to use Preview features

Preview features are a good fit when you want early access to a capability that is still being refined, you can test it ahead of a live event, and you're comfortable reporting problems.

Avoid relying on one for the first time during a live show. Roll them out one at a time: one Preview variable is much easier to evaluate than a whole chain of new behavior.

## Troubleshooting

### A Preview feature behaves inconsistently

Check that Preview is on and that you restarted Relay after turning it on. Then check whether the feature depends on another connection, permission, or service, and whether the behavior repeats on demand or only occasionally.

### A Preview feature is missing entirely

- Confirm **Enable preview features** is on under `Relay > Settings` → **Preview**, and restart Relay.
- Some device models only appear when the required hardware or integration is present.
- The YouTube Live Stream Monitor needs a Debug build and your own OAuth client.

### I found a problem

[Open an issue](https://github.com/dbullard/Relay/issues/new/choose) with what you expected, what happened, exact reproduction steps, whether it happens every time, and any screenshots or diagnostics. Use synthetic data and don't post private addresses or customer information.

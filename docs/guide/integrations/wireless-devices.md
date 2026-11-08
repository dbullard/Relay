# Wireless devices: monitor Shure and Sennheiser systems

Use Relay with wireless systems for status, battery, RF, audio, and automation workflows.

Relay supports wireless monitoring workflows so your dashboard can show channel status, battery, RF, and related live information.

## Add a wireless device

1. Open `Relay > Settings`, then select **External Devices**.
2. Click `Add Device`.
3. Choose the brand — Shure or Sennheiser — and the specific model.
4. Enter the host and port, or use network discovery where supported.
5. Save the device, then add a wireless module to a tile and select it.

## Shure workflows

Shure devices can be added manually or discovered on the network. Once configured, modules can show:

- Device name
- Channel name
- Frequency
- Battery
- RF and audio information

A dedicated `Shure Overview` module (Debug builds only) gives a higher-level summary across multiple devices and channels. It is useful when you want one tile to surface warning states, battery concerns, stale telemetry, or offline channels without building a wall of individual Shure tiles. Relay uses a centralized polling system for Shure wireless devices featuring dynamic tiers for greater efficiency. This optimizes performance by skipping redundant polling and prioritizing the devices you are actively monitoring.

### Shure monitoring details

- **Finer mic meter:** The mic meter now has 10 segments with a -60 dBFS floor, so quiet signals read more clearly.
- **More accurate readings:** RF and battery readings are improved for AD4Q, Axient, and QLX-D.
- **Self-healing connections:** Stuck connections reconnect on their own.
- **Reliable Overview polling:** Overview polling no longer starves channels or misses presence updates.
- **ANX4 defaults to TCP.**

## Sennheiser workflows

Sennheiser support covers three device families, each communicating over a different protocol and default port:

- **EW-DX / Digital 6000** — EW-DX EM 2, EM 2 Dante, EM 4 Dante, and Digital 6000 (EM 6000), over UDP port 45 (EW-DX) or 6970 (Digital 6000).
- **Evolution Wireless G3/G4** — EW G4 100/300/500 Series and EW G3, over UDP port 53212.
- **IEM families** — EW IEM G4, SR IEM G4, 2000 IEM Series, EK 300 IEM G3, and XS Wireless IEM, also over port 53212.

Relay auto-selects the default port for the chosen model; override it only if your network requires a different one.

> [!NOTE]
> Sennheiser is available in all builds but carries a beta badge in the module picker and device list. Test it on your own network before relying on it live.

### Spectera monitoring

Relay monitors Sennheiser Spectera systems:

- Live state updates
- Pinned certificate trust
- Authenticated connection tests
- Diagnostics logging

## Availability notes

- Shure `ANX4`, `ADTD`, and `ADTQ` models appear only when Preview features are on (`Relay > Settings` → **Preview**) or in Debug builds.
- The `Shure Overview` module is in Debug builds only.
- Verbose wireless diagnostics logging controls appear on the **Preview** settings page when Preview is on, and take effect after you restart Relay.

## Automation tie-ins

Wireless systems can feed trigger conditions and destination commands in Automation View depending on the device and build. In Live Mode, Relay suggests wireless telemetry variables you can use in text inputs and automations — see [Shared values and variables](../dashboards/variables.md).

## Troubleshooting

If wireless data is missing, confirm the device is added, reachable, selected in the module, and available in the current build type.

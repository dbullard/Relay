# Wireless Modules

Modules for monitoring Shure and Sennheiser wireless microphone and IEM systems.

Monitor the health of your wireless audio systems, including RF strength, battery life, and audio levels.

> [!NOTE]
> The standalone **Shure** module is stable. **Shure Overview** (the multi-device summary) and **Sennheiser** remain Preview — see each section below.

## Shure

A detailed module for monitoring a single Shure wireless channel.

### Setup
1. Add the **Shure** module to a tile.
2. Select a specific discovered Shure receiver and channel.

### Features
- **Granular Data:** Displays detailed RF strength, exact battery percentage/runtime, and audio metering.
- **10-segment mic meter:** The audio meter uses 10 segments with a -60 dBFS floor for finer readings on quiet signals.
- **Transmitter Info:** Shows the linked transmitter type and frequency band.
- **Per-channel visibility toggles:** Independently show or hide device name, channel name, IP/port, frequency, battery, RF strength, and the audio meter — useful for a compact tile that only needs one or two pieces of data.
- **Demo mode:** Preview the module with fake data (a configurable mic/rack name, battery percentage, and frequency) before a real device is connected, so you can build a layout ahead of time.

---

## Shure Overview `Preview`

A centralized module for monitoring multiple Shure wireless devices at once.

### Setup
1. Ensure your Shure receivers are connected to the same network and discovered in **External Devices**.
2. Add the **Shure Overview** module to a large tile.
3. Choose all Shure devices or a specific selection, and pick a default tab (Auto, Mics, or IEMs).

### Features
- **High-Level Summary:** Perfect for catching issues at a glance without building individual tiles for every mic.
- **Dynamic Polling:** Uses optimized `METER_RATE` tiers to efficiently surface warning states, low batteries, or offline channels while reducing network load.
- **Thresholds:** Separate low-battery and critical-battery percentages (default 30% / 15%), and low-RF and critical-RF thresholds (default level 2 / level 1), each driving the severity coloring on a channel.
- **Stale telemetry timeout:** A channel is flagged stale if it hasn't reported in 8 seconds by default.
- **Audio activity display:** Choose Off, Signal Light, or Meter for how a channel's live audio activity is shown.
- **Sort order:** Severity, Device & Channel, Name, Battery, or RF.
- **Display:** List or card layout, with small/medium/large card sizing, and a toggle to hide offline channels entirely.
- **Person assignment:** Link a channel directly to a person, so the overview can show who's wearing which mic.

---

## Sennheiser `Preview`

Provides monitoring for Sennheiser wireless systems — see [Wireless Devices](../../integrations/wireless-devices.md#sennheiser-workflows) for the full supported model catalog and connection details.

### Setup
1. Add the **Sennheiser** module to a tile.
2. Select your networked Sennheiser receiver.

### Features
- **Status Monitoring:** Tracks battery life, RF, and AF levels for supported Sennheiser receivers.
- **Spectera:** Live state updates for Spectera systems, with pinned certificate trust and authenticated connection tests.
- **Preview only:** This module is only available when Preview features are on, or in Debug builds.

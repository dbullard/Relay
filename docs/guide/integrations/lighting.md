# Smart lights: control Philips Hue and Govee from Relay

Use smart light control as an automation destination to change colors, brightness, and scenes.

> [!WARNING]
> Smart Light Control carries a beta badge and is a Preview feature: it appears only after you turn on `Relay > Settings` → **Preview** and restart Relay. Test it before you rely on it in a live show.

Control your environment's lighting from an automation graph.

## Requirements

- Preview features turned on (`Relay > Settings` → **Preview**, then restart Relay).
- A supported smart light bridge on your network, or a Govee API key. See [Integrations that need your own credentials](../../INTEGRATIONS.md#smart-lights).

## Setup

1. Connect to a supported smart light bridge on your network.
2. In [Automation View](../dashboards/automation.md), add the **Smart Light Control** action node.
3. Choose the lights or scene you want to change.

## What it can do

Set colors, adjust brightness, or recall scenes on Philips Hue or Govee devices, with more providers planned, as part of any automation flow. For example, turn the booth lights red when a wireless mic battery dies.

## Related

- [Action nodes](../dashboards/nodes/actions.md#smart-light-control-beta) for the node reference
- [Wireless devices](wireless-devices.md) to feed battery and RF triggers

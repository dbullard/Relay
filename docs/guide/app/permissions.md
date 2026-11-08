# macOS permissions Relay needs

Review which macOS permissions Relay requires and why they matter.

Relay requests a small set of macOS permissions for audio monitoring, live transcription, and local network discovery.

## Review permissions inside Relay

Open `Relay > Settings`, then select **Access** to see the status of each permission. You can also review the same permissions directly in macOS under `System Settings > Privacy & Security`.

## Main permissions

### Microphone

Needed for SPL Meter and microphone-based transcription workflows.

### Speech Recognition

Needed for Live Transcription.

### Local Network

Needed for:

- device discovery
- LAN sharing
- ProPresenter discovery
- OSC and MIDI network workflows
- other network integrations

### Screen and system audio capture

May be required for system-audio transcription workflows depending on how audio is sourced. Unlike the permissions above, this one doesn't have its own row in **Access**, under `Relay > Settings` — check its status directly in macOS under `System Settings > Privacy & Security > Screen & System Audio Recording`.

## After changing a permission

Quit and reopen Relay, then test again.

## Usage diagnostics

Separate from macOS permissions, `Relay > Settings` → **Access** also has a **Share Crash and Usage Diagnostics** toggle. The first time it comes up, Relay shows a one-time prompt so you can choose before anything is shared, and you can change your answer at any time from that same toggle.

Community builds have no hosted backend and no Sentry project configured, so nothing is uploaded unless you set up your own. If you do, enabling the toggle shares app version, platform, a random installation ID, active time, and technical crash or hang details. It does **not** include dashboard content, connected-device data, location, audio, or Relay network addresses. See [Sentry](../../INTEGRATIONS.md#sentry-optional) and the privacy notes in the [README](../../../README.md#privacy-and-optional-services).

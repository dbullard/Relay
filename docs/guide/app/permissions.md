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

## Crash and usage reporting

Relay does not collect crash reports or usage data, and it has no analytics. To report a problem, use **Settings → Help → Report a Bug**. That opens a prefilled issue on GitHub, and nothing is sent until you submit it there. GitHub issues are public, so review any diagnostic summary before you include it.

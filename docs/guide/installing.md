# Install Relay

Relay is a free macOS app. You don't need an account, license key, or subscription.

**Requirements:** a Mac running macOS 15.6 or later. Relay is signed and notarized by Apple, so macOS opens it without any security workaround.

## Install

1. Open the [latest release](https://github.com/dbullard/Relay/releases/latest) and download `Relay-<version>.zip`.
2. Double-click the zip to unpack it, then drag **Relay** into your **Applications** folder.
3. Open Relay.

> [!NOTE]
> If you already have an earlier Relay (version 1.3 or older) in Applications, macOS will ask whether to replace it. See [Moving from Relay 1.3](app/migrating-from-1-3.md) first. Replacing it is fine, and your saved settings can still be imported.

## First launch

- **Permissions.** macOS asks for access only when a feature needs it: Local Network (device discovery and sharing), Microphone and Speech Recognition (audio and transcription), and Screen Recording (system audio). Allow the ones you plan to use. You can review them any time in `Relay > Settings` → **Access**.
- **Diagnostics.** Relay collects nothing and sends nothing on its own. See [Permissions](app/permissions.md).
- **Setup Wizard.** The wizard finds devices on your network, helps you connect services, and builds a first dashboard. Reopen it with `File > Setup Wizard…`. See the [Setup Wizard guide](guides/setup-wizard.md).

## Connect your services

- **Planning Center.** Official releases include Planning Center sign-in. Open `Relay > Settings` → **External Connections** → **Planning Center**, choose **Connect…**, and sign in. If you build Relay from source, or the button says "not configured", register your own app and enter its ID in **Settings → Integrations**. See [Integrations that need your own credentials](../INTEGRATIONS.md).
- **Hardware.** Consoles, wireless systems, ProPresenter, MIDI, and OSC need no keys. Add them under `Relay > Settings` → **External Devices** or let the wizard find them.
- **YouTube Live Stream Monitor.** A [Preview feature](app/preview-features.md) that needs your own Google OAuth client.
- **NDI.** Needs the separately installed NDI runtime. See [NDI](integrations/ndi.md).

## Build your first dashboard

Follow the [Quick start](quickstart.md). It takes you from a blank canvas to a live dashboard.

## Keep Relay up to date

Relay checks this project's GitHub releases. Choose `Relay > Check for Updates…` at any time, or allow automatic checks. See [Updates](app/updates.md).

## Get help or report a problem

- Browse the [guide](README.md) and [Troubleshooting](troubleshooting.md).
- `Relay > Settings` → **Help** → **Report a Bug** opens a prefilled GitHub issue. Nothing is sent until you submit it there. GitHub issues are public, so review any diagnostic summary first.

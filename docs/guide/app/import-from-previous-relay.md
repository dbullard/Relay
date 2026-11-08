# Import from your previous Relay

Relay 2.0 is a separate app from the closed-source Relay you may have used before (version 1.3 or earlier). macOS keeps the two apps' settings apart, so nothing carries over automatically. If the earlier app's settings are found on your Mac, Relay offers to import them the first time it opens. You can also do it later from **Settings → General → Import from Previous Relay…**.

## What is imported

- External devices and their connection settings
- Audio and transcription inputs, shared values and variables
- MIDI, OSC, ProPresenter, Resolume and smart light settings
- Dashboard preferences such as grid, live mode and autosave
- Preview setting and wireless logging choices

## What is not imported

- **Sign-ins.** Planning Center, YouTube and similar connections live in your Keychain and belong to the old app. Reconnect them in Settings.
- **Accounts, licenses and subscriptions.** Relay 2.0 doesn't use them.
- **Dashboards.** These are separate `.relay` files. Open them from the Home screen.
- **LAN pairings.** Pair your computers again.

## How it works

Relay reads the old app's preferences file (`~/Library/Preferences/davidbullard.relay.plist`), copies only the settings listed above, and restarts to apply them. The old app and its data are never changed. Importing again later replaces matching settings in the new app.

# Live Mode: operate your Relay dashboard during production

Use Live Mode to run dashboards during real events with a cleaner, safer operating view.

Live Mode is the operating mode designed for real use during a show, service, or event. It reduces accidental editing and lets live modules do their job during production.

## Turn it on

- Choose `View > Live Mode`
- Or press `Command-L`

## What changes in Live Mode

- Editing controls are reduced
- The dashboard becomes easier to read at a glance
- Live modules can begin updating
- Supported interactive modules remain usable

Examples of modules that are commonly useful in Live Mode: Time, SPL Meter, Live Transcription, Button, and supported interactive webpage modules.

## Open the live menu

The live menu holds tab switching, settings, and the button to leave Live Mode. It stays hidden until you ask for it. To open it:

- Tap or click the small handle at the top center of the screen. It dims after a few seconds but is always there.
- Drag down from the top center of the screen.
- Rest the pointer at the top center of the screen.

The menu hides again on its own after a few seconds.

## Full screen and the macOS menu bar

When **Settings → General → Live Mode → Window** is set to **Full Screen**, Relay hides the macOS menu bar and Dock while Live Mode is on. That way, reaching for the top of the screen opens Relay's live menu instead of the macOS menu bar. The menu bar comes back when you leave Live Mode.

While the menu bar is hidden, the window's title bar and green full-screen button don't appear either. To leave full screen:

- Leave Live Mode from the live menu, or press `Command-L`.
- Or press `Control-Command-F` to leave full screen and stay in Live Mode.

Keyboard shortcuts keep working the whole time.

## Use a touch screen

Relay works with touch monitors on the Mac, such as screens that use the UPDD driver:

- Pinch with two fingers to zoom the dashboard. Zooming centers on your fingers.
- Drag with two fingers to pan.
- Tap the handle at the top center to open the live menu.

If pinching does nothing, check that your touch driver's gesture settings send pinch as a zoom gesture. To see exactly what Relay receives, turn on touch-input logging in Terminal, then quit and reopen Relay:

```sh
defaults write app.relay.Relay RelayTouchInputDiagnostics -bool YES
```

Pinch once on the dashboard, then open Console.app and search for `touch-input`. Include those lines when you report a problem. Turn logging off again with:

```sh
defaults delete app.relay.Relay RelayTouchInputDiagnostics
```

## Recommended workflow

1. Build and test in Canvas View first.
2. Confirm every important integration is connected.
3. Verify the active tab is the correct one.
4. Enter Live Mode before the event starts.
5. Exit only when you need to edit the dashboard.

## What Live Mode does not fix

Live Mode improves the operating experience, but it doesn't replace missing setup. If something is blank or stale, the underlying issue is usually one of these:

- The module is not configured
- The connected service has no relevant data
- The device is offline or unreachable
- macOS permissions are not granted
- The selected tab is not the one you expected

> [!WARNING]
> If a module depends on network access, audio input, or macOS permissions, Live Mode alone will not fix missing data. You still need the underlying connection or permission in place.

## Troubleshooting

### A live module is not updating

Check that Live Mode is enabled, the module is configured correctly, the target service or device is reachable, and Relay has the required permissions.

### I still need to click around too much in Live Mode

That usually means the dashboard needs one more editing pass. Simplify the layout, enlarge the most important information, or split the workflow across tabs.

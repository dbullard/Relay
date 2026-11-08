# Development setup

## Project layout

- `Dashboard/`: shared application UI, modules, automation, and integrations.
- `Relay/`: bridging header and entitlements.
- `RelayTests/`: macOS tests and synthetic integration fixtures.
- `TranscriptionHelper/` and `TranscriptionShared/`: helper-process transcription code.
- `ThirdParty/NDI/include/`: vendor headers with their original license notices.
- `Config/`: safe defaults and an example for local service configuration.
- `docs/guide/`: user documentation in plain Markdown. See [docs/guide/README.md](guide/README.md).

Use the `Relay` scheme for everything. Debug and Release builds behave the same: the former Beta and Debug-only features are all behind **Settings → Preview**.

## Optional local service configuration

Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`. The latter is gitignored and optionally included by `Config/Community.xcconfig`. Supply only your own service settings. In xcconfig, write URL slashes as `https:/$()/example.com` to avoid interpreting `//` as a comment.

By default the hosted backend and OAuth clients are unconfigured. Relay has no crash-reporting service: bug reports go to GitHub issues. In-app updates read the appcast attached to the latest GitHub release (`SUFeedURL`), and an update installs only if it is signed with the project's Sparkle key.

Planning Center and YouTube sign-in require your own OAuth apps. See [integrations that need your own credentials](INTEGRATIONS.md) for step-by-step setup.

The core app works without these services. This repository does not include the private backend, server credentials, release signing configuration, or notarization credentials.

## Bundle identifiers

The app uses `app.relay.Relay`, the transcription helper `app.relay.Relay.TranscriptionHelper`, and tests `app.relay.RelayTests`. Sparkle's installer services and the helper's XPC service name derive from these, so change them together (project build settings, `Relay/RelayRelease.entitlements`, and the XPC name in `Dashboard/Modules/XPCSpeechTranscriberAdapter.swift`). Forks that ship their own builds should use their own identifiers so macOS permissions, Keychain items, and settings don't collide with the upstream app.

Earlier builds used a different identifier. Because settings, permissions, and Keychain items are tied to the bundle identifier, anyone moving from an earlier build starts with fresh settings and reconnects their integrations.

## NDI runtime

The macOS receiver dynamically loads NDI. The proprietary runtime is intentionally omitted from Git and the mandatory Xcode copy phase was removed, so the basic app can build without it. Without a runtime, NDI reports unavailable; other modules remain usable.

Obtain a compatible NDI 6 runtime from the official [NDI developer downloads](https://ndi.video/for-developers/ndi-sdk/download/) under its terms. For local testing, set `NDI_RUNTIME_DIR_V6` in your Xcode scheme environment to the directory containing `libndi.dylib`, or install it in a standard location such as `/usr/local/lib`. Local runtime files under `ThirdParty/NDI/lib/` are ignored, but are not automatically bundled.

Do not add SDK binaries to Git. Packaging NDI in a signed distribution is a separate licensing/packaging step. See NDI's [licensing](https://docs.ndi.video/all/developing-with-ndi/sdk/licensing) and [distribution requirements](https://docs.ndi.video/all/developing-with-ndi/sdk/software-distribution).

## Known limitations

Relay Mobile builds for the iOS Simulator (CI checks this) but is experimental: it hasn't been tested on devices and isn't a supported release target yet. When you add a Swift file that the Mobile target needs, add it to the Mobile target's file list (the "Exceptions for Dashboard folder in Relay Mobile target" entry in `Relay.xcodeproj/project.pbxproj`, or tick the Mobile target in Xcode's File inspector). The iOS NDI integration also requires the separately licensed iOS SDK; the static library is not included.

Some Release behavior is channel-dependent and cannot be verified solely with Debug tests: Preview defaults, crash consent, and configured manual-report delivery need a Release check. Manual verification on real consoles, receivers, and NDI sources is welcome; most contributors will not have every device.

## Before a release

Run the tests and the manual checks in `docs/RELEASE_CHECKLIST.md`. The Debug entitlements deliberately omit the restricted `com.apple.developer.networking.multicast` entitlement: with it, a locally signed build fails to launch (launchd error 163) unless your team has Apple's approval. Release builds are Developer ID signed with no restricted entitlements. Official binaries require an authorized Apple signing identity, notarization, and an explicit release decision. A source push is not an app release.

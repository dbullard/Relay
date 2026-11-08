# Development setup

## Project layout

- `Dashboard/`: shared application UI, modules, automation, and integrations.
- `Relay/`: bridging header and entitlements.
- `RelayTests/`: macOS tests and synthetic integration fixtures.
- `TranscriptionHelper/` and `TranscriptionShared/`: helper-process transcription code.
- `ThirdParty/NDI/include/`: vendor headers with their original license notices.
- `Config/`: safe defaults and an example for local service configuration.
- `docs/guide/`: user documentation in plain Markdown. See [docs/guide/README.md](guide/README.md).

The shipping scheme is `Relay`; local development uses `Relay (DEBUG)`. Both are free. The removed Beta scheme is replaced by the Preview setting.

## Optional local service configuration

Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`. The latter is gitignored and optionally included by `Config/Community.xcconfig`. Supply only your own service settings. In xcconfig, write URL slashes as `https:/$()/example.com` to avoid interpreting `//` as a comment.

By default Sentry, Sparkle's remote update feed, OAuth clients, and the hosted backend are unconfigured. Sentry also remains disabled in Debug builds even if you supply a DSN. Testing actual crash/feedback delivery requires a locally configured Release build and an intentional submission to your own Sentry project. Builds never automatically upload debug symbols to the original maintainer's Sentry project.

Planning Center and YouTube sign-in require your own OAuth apps. See [integrations that need your own credentials](INTEGRATIONS.md) for step-by-step setup. A backend URL alone does not enable Relay Account sign-in: the `RELAY_ACCOUNT_AUTH_ENABLED` plist flag is false. Account/licensing service code remains for compatibility but is not required to unlock features. The fallback account URL points only to localhost.

The core app works without these services. This repository does not include the private backend, server credentials, release signing configuration, or notarization credentials.

## NDI runtime

The macOS receiver dynamically loads NDI. The proprietary runtime is intentionally omitted from Git and the mandatory Xcode copy phase was removed, so the basic app can build without it. Without a runtime, NDI reports unavailable; other modules remain usable.

Obtain a compatible NDI 6 runtime from the official [NDI developer downloads](https://ndi.video/for-developers/ndi-sdk/download/) under its terms. For local testing, set `NDI_RUNTIME_DIR_V6` in your Xcode scheme environment to the directory containing `libndi.dylib`, or install it in a standard location such as `/usr/local/lib`. Local runtime files under `ThirdParty/NDI/lib/` are ignored, but are not automatically bundled.

Do not add SDK binaries to Git. Packaging NDI in a signed distribution is a separate licensing/packaging step. See NDI's [licensing](https://docs.ndi.video/all/developing-with-ndi/sdk/licensing) and [distribution requirements](https://docs.ndi.video/all/developing-with-ndi/sdk/software-distribution).

## Known limitations

Relay Mobile currently fails to build due to pre-existing missing LiveMode behavior, Spectera, ProfanityFilter, and related types. It is not a supported release target yet. The iOS NDI integration also requires the separately licensed iOS SDK; the static library is not included.

Some Release behavior is channel-dependent and cannot be verified solely with Debug tests: Preview defaults, crash consent, and configured manual-report delivery need a Release check. Manual verification on real consoles, receivers, and NDI sources is welcome; most contributors will not have every device.

## Before a release

Run the tests and the manual checks in `docs/RELEASE_CHECKLIST.md`. Official binaries require an authorized Apple signing identity, notarization, and an explicit release decision. A source push is not an app release.

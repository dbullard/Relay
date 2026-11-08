# Release checklist

A source push is not a signed app release. There is no automatic deployment or distribution workflow in this repository.

- [ ] Mac build and full tests pass with the committed package versions.
- [ ] Test a Release build with no license, no account, and no internet: free features remain available.
- [ ] Verify Preview off/on with restart, including preserved saved DAW protocols.
- [ ] Verify Support points to this repository and contains no personal-payment prompt.
- [ ] Verify **Settings → Help → Report a Bug** opens a prefilled GitHub issue.
- [ ] Confirm app version/build, release notes, minimum OS, and known limitations.
- [ ] Set the release's integration credentials (for example `PCO_OAUTH_CLIENT_ID`) in your gitignored `Config/Local.xcconfig`, build, and confirm they are in the built Info.plist. See [Maintainers: official releases](INTEGRATIONS.md#maintainers-official-releases-and-existing-users).
- [ ] Decide whether upgrading users keep their Planning Center login (same client ID) or reconnect once (new client ID). Do not revoke an older client ID while releases using it are still installed.
- [ ] Verify Planning Center sign-in on a clean Mac with no setup.
- [ ] Keep the same bundle identifier (`app.relay.Relay`) and signing identity as the previous release so users keep their settings.
- [ ] Review dependency licenses, NDI runtime packaging, and required notices.
- [ ] Sign and notarize using an authorized release identity.
- [ ] Verify the signed download on a separate Mac.
- [ ] Publish a release only after maintainers explicitly approve it; never commit credentials, signatures, or proprietary runtime binaries to source.

The old paid release's subscription wind-down and legacy server rollout are managed separately in the private legacy repository. No user data or private operational runbooks are copied here.

## Publishing an update

In-app updates read `appcast.xml` from the latest GitHub release (`SUFeedURL`), so each release must attach it. You need the Sparkle private key that matches `SUPublicEDKey` (kept in your Keychain by Sparkle's `generate_keys`).

1. Bump the version and build number, build the Release configuration, sign with Developer ID, and notarize.
2. Zip the app: `ditto -c -k --keepParent Relay.app Relay-X.Y.Z.zip`.
3. Put the zip in an empty folder and run Sparkle's `generate_appcast` on it, with the download prefix set to the release's asset URL:
   `generate_appcast --download-url-prefix https://github.com/dbullard/Relay/releases/download/vX.Y.Z/ <folder>`
4. Create the GitHub release (not a draft or pre-release; `releases/latest` ignores those) and attach both `Relay-X.Y.Z.zip` and `appcast.xml`.
5. On a Mac with the previous version installed, choose **Relay → Check for Updates…** and confirm it offers the new version and installs it.

People on the old app (`davidbullard.relay`) can't update to this app, because the bundle identifier differs. They install it once as a new app.

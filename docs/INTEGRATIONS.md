# Integrations that need your own credentials

Relay does not ship any API keys, OAuth clients, or hosted-service settings. Everything below uses **your own** accounts, so nothing in a build is tied to the original maintainer. Unconfigured integrations simply show a "not configured" message; the rest of the app is unaffected.

**Easiest way:** open **Settings → Integrations** in Relay and paste your Planning Center client ID (and, with Preview on, your YouTube client ID). It takes effect immediately, with no rebuild.

If you build Relay yourself, you can also set build-time values in `Config/Local.xcconfig` (gitignored). They are used whenever the matching field in Settings is empty. Copy the example first:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

In xcconfig files, write URL slashes as `https:/$()/example.com`, because `//` starts a comment. Rebuild after changing values. Never commit `Local.xcconfig` or paste secrets into issues.

| Integration | Needs | Where it is set |
|---|---|---|
| [Planning Center](#planning-center-pco) | Your own PCO OAuth app | Settings → Integrations (or `PCO_OAUTH_CLIENT_ID` in `Local.xcconfig`) |
| [YouTube Stream Monitor](#youtube-stream-monitor) | Your own Google OAuth client | Settings → Integrations with Preview on (or `YOUTUBE_OAUTH_*` in `Local.xcconfig`) |
| [Sparkle updates](#sparkle-updates) | Only if you ship your own fork | `SUFeedURL` and `SUPublicEDKey` |
| [Hue and Govee smart lights](#smart-lights) | A Hue bridge, or a Govee API key | Entered in the app |
| [NDI](#ndi) | The NDI runtime | See [DEVELOPMENT.md](DEVELOPMENT.md#ndi-runtime) |

Hardware integrations (ProPresenter, Resolume, audio consoles, wireless systems, MIDI) need no keys. You enter the device address in the app.

## Planning Center (PCO)

Relay signs in with OAuth (PKCE), so no client secret is needed.

1. Sign in to the [Planning Center developer portal](https://api.planningcenteronline.com/oauth/applications) and create a **new OAuth application**.
2. Set the **Redirect URI** to exactly: `app.relay.pco://oauth/callback`
3. Copy the application's **Client ID** (the Client Secret is not used).
4. Open **Settings → Integrations**, paste the Client ID, and click **Save**. (Building from source? You can set `PCO_OAUTH_CLIENT_ID = your_client_id` in `Config/Local.xcconfig` and rebuild instead.)
5. Open **Settings → External Connections → Planning Center** and choose **Connect…**.

The scopes requested are `services` and `people`. Your Planning Center account needs access to those products. The access token is stored in your macOS Keychain, not in the repository.

If you skip this, **Connect…** shows: "Planning Center sign-in is not configured".

![Planning Center settings showing the not-configured message](images/pco-not-configured.jpg)

## YouTube Stream Monitor

This module is a Preview feature. Turn on **Settings → Preview** and restart Relay.

1. In the [Google Cloud console](https://console.cloud.google.com/), create a project and enable the **YouTube Data API v3**.
2. Configure the OAuth consent screen. While the app is in "Testing" status, add your own Google account as a test user.
3. Create an **OAuth client ID** for your platform. The scope Relay requests is read-only: `https://www.googleapis.com/auth/youtube.readonly`.
4. In `Config/Local.xcconfig`, set the values that apply (macOS shown):

   ```
   YOUTUBE_OAUTH_CLIENT_ID_MACOS = your_client_id
   YOUTUBE_OAUTH_CLIENT_SECRET_MACOS = your_client_secret_if_your_client_type_has_one
   YOUTUBE_OAUTH_REDIRECT_URI_MACOS = your_registered_redirect_uri
   ```

   The default redirect is `app.relay.youtube:/oauth2redirect`, and that scheme is declared in `Relay-Info.plist`. If you register a different redirect, its URL scheme must also be added to the app's URL Types.
5. Rebuild, then open **Settings → External Connections → Live Stream** and choose **Connect YouTube…**.

iOS uses the matching `YOUTUBE_OAUTH_CLIENT_ID_IOS`, `YOUTUBE_OAUTH_REDIRECT_URI_IOS`, and `YOUTUBE_OAUTH_CALLBACK_SCHEME` keys. Relay Mobile is experimental and does not currently build.

## Sparkle updates

Relay checks `SUFeedURL` for updates. The default, in `Config/Community.xcconfig`, is the `appcast.xml` attached to the latest GitHub release:

```
https://github.com/dbullard/Relay/releases/latest/download/appcast.xml
```

An update installs only if it is signed with the private key matching `SUPublicEDKey` in `Relay-Info.plist`, so a fork cannot push updates to official installs. If you ship your own fork, generate your own key pair with Sparkle's `generate_keys`, replace `SUPublicEDKey`, and set your own `SUFeedURL` in `Local.xcconfig`. Keep your private key out of the repository. Maintainers publish updates as described in [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md#publishing-an-update).

## Smart lights

- **Philips Hue:** no key to obtain ahead of time. In Relay, press the link button on your Hue bridge, then pair. Relay talks to the bridge over your local network.
- **Govee:** create an API key in the Govee Developer settings, then enter it in Relay's Settings → External Connections → Smart Lights. It is stored in your Keychain.

## NDI

NDI needs the separately licensed runtime. See [NDI runtime](DEVELOPMENT.md#ndi-runtime).

## Maintainers: official releases and existing users

Source builds ship with no Planning Center client ID, so contributors and forks register their own. A distributed release is different: people who download it should not have to register anything. Those builds get the maintainer's client ID at build time, from the maintainer's gitignored `Config/Local.xcconfig`. Never commit the file or the ID-bearing build settings.

When preparing a release:

1. Put the release's `PCO_OAUTH_CLIENT_ID` (and any other credentials the release should include) in `Config/Local.xcconfig`, then build the Release configuration.
2. Confirm the built app contains it: `/usr/libexec/PlistBuddy -c "Print :PCO_OAUTH_CLIENT_ID" Relay.app/Contents/Info.plist`.
3. Confirm a clean machine can sign in to Planning Center with no setup.

**Keeping existing users signed in.** Saved Planning Center tokens belong to the client ID that issued them. People upgrading from an earlier release keep their connection only if the new release uses the same client ID. Choose one:

- **Same client ID (no reconnect):** use the original app's client ID in the release build, and add the current callback URL, `app.relay.pco://oauth/callback`, to that Planning Center app's callback list. Old tokens keep refreshing.
- **New client ID (one reconnect):** use a new Planning Center app. Upgrading users click **Connect…** once. Dashboards and other settings are unaffected.

**Do not revoke, regenerate, or delete an older Planning Center client ID while any release that uses it is still installed.** Planning Center would stop accepting those apps' sign-ins and token refreshes. Retire an old client only after the releases using it are out of use.

Dashboards and settings carry over only if the release keeps the same bundle identifier and signing identity as the previous one. A build signed by a different developer starts with empty data.

## Troubleshooting

- **A field in the app says "not configured":** the matching value is blank, or you did not rebuild after editing `Local.xcconfig`. Check `Config/Local.xcconfig` is in the `Config/` folder and has no stray spaces or quotes.
- **OAuth sign-in opens a browser and then fails to return:** the redirect URI registered with the provider must match the one above exactly.
- **Switching OAuth apps:** disconnect in Settings and connect again, because saved tokens belong to the app that issued them.

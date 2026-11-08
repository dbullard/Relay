# Updating Relay: getting new versions

The community edition of Relay does not update itself unless you configure an update feed. This page explains how to get new versions and what to check when an update goes wrong.

## Updating a source build

1. Pull the latest changes from the repository.
2. Rebuild in Xcode, or with the `xcodebuild` command in the [README](../../../README.md).

If you downloaded a prebuilt app from a release, download the newest release and replace the old copy in your Applications folder.

## Check for updates

`Relay > Check for Updates...` only works in builds that were given an update feed. Source builds have none by default, so the command has nothing to check. A maintainer or fork that wants automatic updates sets that up themselves; see [Sparkle updates](../../INTEGRATIONS.md#sparkle-updates-optional).

## What changed

Release notes live with each release on the project's [GitHub releases page](https://github.com/dbullard/Relay/releases). For changes between releases, see the commit history.

## Preview features after an update

Updating doesn't change your **Enable preview features** setting. If a Preview feature stops appearing after an update, check `Relay > Settings` → **Preview** and restart Relay. See [Preview features](preview-features.md).

## Troubleshooting

If an update fails, make sure Relay is installed in the Applications folder and not still being run directly from a disk image, or from a build folder.

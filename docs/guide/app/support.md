# Getting help: troubleshooting, logs, and reporting issues

Work through common issues, export diagnostic logs, and report problems to the community.

## Start with the simplest check

When Relay isn't behaving the way you expect, start here:

1. Confirm you're on the expected tab.
2. Confirm the module or integration is configured.
3. Confirm the outside device or service is reachable.
4. Confirm macOS permissions are allowed under `Relay > Settings` → **Access**.
5. Test again in Live Mode if the feature depends on it.

## Common issue patterns

### A module is blank

Usually means one of these:

- The module is added but not configured
- The connected service has no data for the active tab
- The target device is offline or unreachable
- Live Mode is required for updates

### A network integration will not connect

Check:

- Host or IP address
- Port
- Credentials, if the system requires them
- Same-network access
- Local Network permission on macOS

### Automation does not fire

Check:

- The trigger type matches what you're sending
- The correct source device is selected
- Nodes are connected and configured

### A feature is missing

Some newer features appear only when Preview is on. Check `Relay > Settings` → **Preview**, then restart Relay. See [Preview features](preview-features.md).

## Export logs

1. Choose `Help > Export Logs...`.
2. Save the archive.
3. Attach it to your issue if a maintainer asks for it, after reviewing it (see below).

You can also find log tools under `Relay > Settings` → **Help**.

## Copy a diagnostic summary

Open `Relay > Settings` → **Help** and click `Copy Diagnostic Summary` for a quick text snapshot of current state — lighter weight than a full log export, useful for a fast first look.

## What logs may include

Logs can include connection endpoints, device names, LAN activity, OSC paths, wireless diagnostics, app errors, and update-related details.

> [!WARNING]
> Review logs before sharing if your environment includes sensitive device names, addresses, or other production details.

## When to export logs

Export the full log archive rather than just a diagnostic summary when:

- A device or service repeatedly fails to connect
- Relay behaves differently than expected after an update
- A maintainer asks for deeper troubleshooting data

## Get help or report a problem

If you've worked through the checks above and still need help:

- **Bugs and questions:** [open an issue](https://github.com/dbullard/Relay/issues/new/choose) on GitHub.
- **Security problems:** use [private vulnerability reporting](https://github.com/dbullard/Relay/security/advisories/new), not a public issue. See [SECURITY.md](../../../SECURITY.md).
- **Conduct concerns and the in-app support email:** `support@ondeckapps.com`.

This is a community project. There are no response-time guarantees, and not every device can be supported.

Include as much of this as you can:

- What you expected to happen
- What actually happened
- Screenshots (without private information)
- App version
- Device or service involved
- Diagnostic summary or exported logs if available

> [!TIP]
> When testing a problem, change one thing at a time. That makes it much easier to tell whether the issue is with Relay, the device, the network, or the surrounding environment.

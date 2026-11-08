# Quick start: install Relay and build your first dashboard

Open Relay, create a dashboard, add a tile and module, and enter Live Mode.

This guide walks you through Relay from first launch to running your first live dashboard.

#### Step 1: Open Relay

Launch Relay on your Mac. If the system asks for permissions, allow the prompts that match the workflows you plan to use.

> [!TIP]
> Relay may need Local Network, Microphone, or Speech Recognition access depending on which modules or integrations you use. You can review permission status at any time under `Relay > Settings` → **Access**.

#### Step 2: Run the Setup Wizard (optional)

The [Setup Wizard](guides/setup-wizard.md) can do most of the setup for you. It walks you through connecting your services, choosing starter tiles with a live layout preview, and creating your first dashboard. Every step is optional.

> [!TIP]
> You can reopen the wizard at any time with `File > Setup Wizard…`.

#### Step 3: Create a new dashboard

Choose `File > New Dashboard`. If prompted, choose a canvas size that fits your display or planned operating view.

Save the dashboard early with `File > Save Dashboard` or `Command-S` so you have a real `.relay` file before you build further.

#### Step 4: Add a tile

In Canvas View, use the toolbar to add a tile. Drag it into position and resize it until it feels readable for the actual distance where it will be used.

#### Step 5: Add a module

Select the tile, open the add-module control, and choose a module such as Time, Text, Document, Webpage, Planning Center, or ProPresenter.

#### Step 6: Configure the connections you need

Open `Relay > Settings` and connect only the systems you actually plan to use first, such as Planning Center, ProPresenter, devices, OSC, MIDI, or LAN sharing.

#### Step 7: Enter Live Mode

Choose `View > Live Mode` or use `Command-L` when the dashboard is ready for production use.

## Design a good first layout

For most teams, a helpful first dashboard includes:

- One large tile for the most important live information
- One or two supporting tiles for timers, notes, or status
- A simple visual hierarchy that can be understood at a glance

Good starter modules are Text, Time, Webpage, Document, Planning Center, and ProPresenter.

Useful habits:

- Keep the most important information in the largest tiles.
- Group related information together.
- Leave enough spacing so the screen is readable from a distance.
- Use separate tabs for different moments in your workflow.

> [!TIP]
> If a dashboard feels crowded, split it into multiple tabs instead of trying to fit everything onto one screen.

## Next steps

- [Core concepts](core-concepts.md) — Learn the terms used throughout the docs.
- [Tiles](dashboards/tiles.md) — Arrange, resize, and align tiles.
- [Automation](dashboards/automation.md) — Make Relay respond to events.
- [Troubleshooting](troubleshooting.md) — Fix common problems.

## Troubleshooting

If a feature does not work after granting a permission, quit and reopen Relay. If live data still does not appear, confirm the integration is configured in settings and that the target system is reachable on the network.

# YouTube Live: monitor stream health and viewers

Monitor viewer count, chat activity, and stream health for a live broadcast from your dashboard.

> [!WARNING]
> The YouTube Live Stream Monitor is a Preview feature (turn on **Settings → Preview** and restart), and needs your own Google OAuth client ([setup steps](../../INTEGRATIONS.md#youtube-stream-monitor)). Test it before you rely on it in a live show.

Keep an eye on your live broadcasts directly from your dashboard, so you can confirm your stream is healthy and track viewer engagement.

## Setup

1. Add a **YouTube Live Stream Monitor** module to a tile.
2. In the inspector, authenticate Relay with your Google/YouTube account.
3. Use the broadcast picker to select your active or upcoming stream.

## Features

- **Live statistics:** Concurrent viewers, total likes, and chat activity.
- **Stream health:** Incoming video bitrate and overall connection quality.
- **Fast loading:** The broadcast picker loads results quickly and filters out streams that have already ended.
- **Persistence:** Your previously selected broadcast stays in the picker even if it momentarily drops from the active results list.

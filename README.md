# TTT2 Stats Addon

The Garry's Mod companion addon for [TTT Stats](https://github.com/WieseChristoph/ttt-stats). It records TTT2 rounds, player and weapon statistics, deaths, role changes, revivals, and the teams involved at the time of each event.

Failed uploads are stored on disk and retried, so temporary website downtime does not lose completed rounds.

## Installation

Install the addon directly in the server's addon directory:

```bash
cd garrysmod/addons
git clone https://github.com/WieseChristoph/ttt2-stats-addon.git ttt2-stats
```

Start the server once to create `garrysmod/data/ttt2_stats/config.json`, then configure it:

```json
{
    "website": "https://stats.example.com",
    "token": "replace-with-the-server-token",
    "logLevel": "INFO"
}
```

- `website` is the public URL of the [TTT Stats website](https://github.com/WieseChristoph/ttt-stats), without an API path.
- `token` must exactly match the website's `STATS_INGEST_TOKEN`.
- `logLevel` can be `DEBUG`, `INFO`, `WARN`, or `ERROR`; it defaults to `INFO`.

Restart the server after changing the configuration. Pending rounds are kept under `garrysmod/data/ttt2_stats/queue` and uploaded automatically when the API is available again.

## Loading screen and player access

Add the loading-screen URL to the server configuration:

```text
sv_loadingurl "https://stats.example.com/loading?mapname=%m&steamid=%s"
```

The map and joining player's Steam ID let the loading screen show relevant statistics. Players can also type `!stats` or press `F4` to open the main website.

## Development

The addon has no build step or external Lua dependencies. Clone or symlink it into a local server's `garrysmod/addons` directory, run the [website development setup](https://github.com/WieseChristoph/ttt-stats#development), and use a local configuration:

```json
{
    "website": "http://localhost:3000",
    "token": "dev-ingest-token",
    "logLevel": "INFO"
}
```

Use the same token in the website's `.env`, then restart or reload the Garry's Mod server after Lua changes.

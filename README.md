# Finals Rank for DankMaterialShell

A DankBar widget and desktop card that tracks your **THE FINALS** leaderboard
standing: rank, score, percentile, movement over a configurable window, recent
trend and the time left in the current season.

The bar pill shows your rank and the season countdown; clicking it opens the full
card.

## Features

- **Live rank and score** from the community leaderboard API, with the game's own
  upstream feed as a fallback during season rollovers.
- **Season countdown** with a progress bar and a configurable season name and
  date range.
- **Percentile** — "top 1.4% of 10,000" — from a separate, cheap board-size
  request.
- **Movement** over 1 hour to 7 days, plus points-per-day once enough samples
  exist.
- **Trend sparklines** for score and rank, built from locally recorded changes.
- **Past seasons** and a career-best Quick Cash rank.
- **Desktop notifications** when your rank changes, posted through DMS so they
  appear in notification history.
- **History stays local** — a small JSONL file in your state directory, pruned by
  age and capped.

## Requirements

- DankMaterialShell `>= 1.2.0`
- `curl` on `PATH`
- Any supported compositor

## Installation

Clone the repository into your DMS plugins directory. The usual locations are
`~/.config/dms/plugins/` or `~/.config/DankMaterialShell/plugins/` depending on
your setup:

```sh
git clone https://github.com/ausbitbank/finalsRank.git \
  ~/.config/dms/plugins/finalsRank
```

Then ask DMS to rescan plugins:

```sh
dms ipc call plugin-scan reload finalsRank
```

If the plugin was already enabled and the new code does not appear, restart the
shell:

```sh
systemctl --user restart dms.service
```

Enable **Finals Rank** in Settings → Plugins, then enter your player name in the
plugin settings. A fresh install shows **No player name set** until you do.

## Configuration

| Setting | Default | Notes |
|---|---|---|
| Player name | *(empty)* | Required. Embark name or platform handle; add `#1234` if the base name is ambiguous. |
| Leaderboard | `s12quickcash` | Season + mode. See below. |
| Platform | `crossplay` | `crossplay`, `steam`, `psn` or `xbox`. |
| Season name | `PRIME TIME` | Display label only. |
| Season start | `2026-10-20T13:00:00Z` | Used for the progress bar. |
| Season end | `2027-01-21T13:00:00Z` | Used for the countdown. Update when Embark announces a date. |
| Refresh interval | 15 min | 5–180 minutes. |
| Show countdown on the bar | on | Adds the time left beside the rank. |
| Show points in the popout | on | Board score for casual modes. |
| Show percentile | on | Costs one small board-size request per board change. |
| Show past seasons | on | Uses the player snapshot endpoint. |
| Include sponsors boards | off | Sponsors boards rank by fans, not performance. |
| Track history | on | Writes the local JSONL change log. |
| Keep history for | 120 days | 7–730 days. |
| Only record changes | on | Off logs every poll. |
| Compare movement over | 24 h | 1–168 hours. |
| Notify on rank change | on | Fires from the bar pill only. |

### Board IDs

`<season><mode>`, for example:

| Board | Meaning |
|---|---|
| `s12quickcash` | Season 12 Quick Cash |
| `s12powershift` | Season 12 Power Shift |
| `s12` | Season 12 Ranked |
| `s12sponsor` | Season 12 Sponsors (ranked by fans, no points) |
| `s11quickcash` | Season 11 Quick Cash (archived, final) |

Quick Cash starts at season 5. Archived boards show where you finished, not how
you progressed through the season.

## Data sources and privacy

The plugin talks only to public endpoints:

| Purpose | Endpoint |
|---|---|
| Live rank and score | `https://api.the-finals-leaderboard.com` |
| Board size (percentile) | `https://api.the-finals-leaderboard.com` |
| Past seasons | `https://api.the-finals-leaderboard.com` |
| Rollover fallback | `https://id.embark.games` |

- **No telemetry, analytics, accounts or API keys.** Only the player name you
  configure is queried.
- **History is local.** It is stored in
  `~/.local/state/DankMaterialShell/plugins/finalsRank/history.jsonl` and is
  never uploaded.
- **Notifications are local.** Rank-change pings are posted through `dms notify`
  to your own desktop notification service.
- Requests are launched with `curl` using an argument array, not a shell, and the
  player name is URL-encoded.

## Limitations

- **Ranks are global, not regional.** No public API exposes the in-game region
  filter; the game computes regional boards client-side from data it does not
  publish.
- **Only the top 10,000 are listed.** Below that line the widget says `off board`
  rather than guessing.
- **Season dates are manual.** There is no public feed for season start/end;
  update the dates when Embark announces a new season or the countdown will be
  wrong.
- **Live boards are cached for about 10 minutes.** Polling faster does not produce
  fresher figures.
- **History only starts when you install the plugin.** The API has no per-player
  history, so "since yesterday" is built from local samples.
- **Sponsors boards carry no points** and are hidden from the past-season list by
  default because they are not comparable with performance boards.

## How it works

- The **live rank** comes from
  `/v1/leaderboard/<board>/<platform>?name=…&exactMatch=true`.
- If that board 404s during a season rollover, the plugin retries the game's
  upstream leaderboard page — crossplay only — and parses the embedded
  `__NEXT_DATA__` payload.
- **Past seasons** come from `/v1/player/<resolvedName>`. That endpoint is a
  periodic snapshot, so it is never used for the current board.
- **History** records a row only when rank or score changes. Deltas compare
  against the newest sample at or before the selected window, falling back to the
  oldest sample when the window is still empty.
- **Trend charts** need at least three recorded changes before they are drawn.
- **Rank is plotted inverted** so that going up means improving, matching the
  score line.

## Development

Architecture notes, QML gotchas, testing details and the release checklist live
in [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

Run the offline tests (Node.js 18+, no dependencies):

```sh
npm test
```

The optional live check needs a player name and network access:

```sh
FINALS_PLAYER='YourName#1234' npm run test:live
```

## License

MIT — see [`LICENSE`](LICENSE).

THE FINALS and its logo are trademarks of Embark Studios. The bundled mark is
used only to identify the game this plugin reads from. This project is not
affiliated with or endorsed by Embark Studios or DankMaterialShell.

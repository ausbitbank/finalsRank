# Development notes

These notes document the architecture and the non-obvious QML behaviour behind
Finals Rank. They are aimed at contributors; user-facing documentation is in the
top-level [`README.md`](../README.md).

## Project layout

```
Logic/
  FinalsLogic.qml    all data, fetching and calculations
  FinalsPanel.qml    the single layout used by both surfaces
  HistoryStore.qml   change-logged history, JSONL on disk
  Sparkline.qml      trend line for the score and rank series
  FinalsLogo.qml     the bundled THE FINALS mark
assets/
  finals-logo.png    the game mark
Widget.qml           bar pill + popout host
DesktopWidget.qml    desktop card host
Settings.qml         settings pane
tests/
  logic.test.js      offline tests for pure helpers and the history store
  live-check.js      optional network check, driven by FINALS_PLAYER
```

Both hosts instantiate `FinalsLogic` as `fd` and pass it to `FinalsPanel` as
`logic`. Neither host re-implements a figure, so the popout and desktop card
cannot drift.

`FinalsLogic` imports its siblings with `import "."`. Writing
`import "./HistoryStore.qml"` fails: QML reads the dotted form as a directory
name. Keeping the shared files flat in `Logic/` is deliberate.

## Panel property and sizing

The panel's property is named `logic`, not `fd`. A property whose name matches
the id of the object passed to it resolves to **null inside an inline
`Component { }`**. `FinalsPanel { logic: fd }` works; `fd: fd` silently assigns
null and renders every label empty with no error.

`FinalsPanel` is an `Item` wrapping a `Column`, so it declares
`implicitHeight: col.implicitHeight + padY * 2`. A bare `Item` leaves that at
zero — the bar popout sizes content from the top down, so the panel would
collapse and only the popout header would remain.

Measured at `popoutWidth` 320 with full data:

| Surface | Past-season rows | Measured | Host sizing |
|---|---|---|---|
| Popout | 3 | ~344px | `popoutHeight: 416` |
| Desktop card | 5 | ~384px | `minHeight: 408`, `defaultHeight: 420` |

The two surfaces are not the same height because `seasonsShown` is 3 on the
popout and 5 on the card. Re-measure both when adding rows, and bump
`popoutHeight`, `minHeight` and `defaultHeight` together.

## Data sources and freshness

Three community-API endpoints, polled independently, plus one fallback. All are
public and keyless:

| Endpoint | Used for |
|---|---|
| `/v1/leaderboard/<board>/<platform>?name=…&exactMatch=true` | live rank and points |
| `/v1/leaderboard/<board>/<platform>?count=true` | board size for the percentile |
| `/v1/player/<resolvedName>` | past seasons, server timestamp |
| `id.embark.games/the-finals/leaderboards/<slug>` | rollover fallback only |

The two families are not equally fresh. `/v1/leaderboard` is live. `/v1/player`
is a periodic snapshot and lagged the live board by roughly 1.5 hours in testing.
The current-board figure therefore always comes from the leaderboard endpoint;
`/v1/player` is used only for season-final numbers and the feed timestamp.

`/v1/player` requires the exact name including the `#discriminator`. A bare
configured name 404s there, so `_parse` captures the canonical `resolvedName` and
the season fetch waits for that rather than guessing.

Two properties of the data:

- **Ranks are global, not regional.** See below.
- **Only the top 10,000 exist.** An empty board is "off board", not an error.

## Regional ranks are not available

There is no public source of regional leaderboards. The API's OpenAPI document
has no region, continent, country or geo parameter; the site's only `region`
strings are ARIA attributes and playtest i18n keys; and the upstream payload's
union of keys across the board contains rank, names, points, club tag and club
UUID only — no region field.

The in-game region filter is computed client-side from an assignment the game
never publishes. No API can serve what the publisher does not expose.

## Season dates are manual

There is no public feed for season start/end, so both are settings with current
defaults baked in. Update them when Embark announces the next season, or the
countdown will be wrong.

The defaults are a consensus estimate where the publisher has not confirmed an
end date. When the real date is known, change `seasonEndIso` in all four places
that carry it:

- `Logic/FinalsLogic.qml`
- `Widget.qml`
- `DesktopWidget.qml`
- `Settings.qml`

Also update the fixtures/defaults in the tests and documentation.

## The rollover gap and the upstream fallback

The community API adds new boards by hand, so for the first days of a season it
can answer 404 for the current board while the game already serves it. On a 404
for a **crossplay** board, the plugin retries the game's own feed before
reporting an error.

Three constraints keep this a narrow fallback rather than a second source:

- **Crossplay only.** Upstream has no platform filter, so a steam/psn/xbox board
  must not fall back; that would silently relabel crossplay figures.
- **Current season's variant boards only.** Archived boards stay on the community
  API, which keeps them permanently.
- **Unknown modes refuse to guess.** `upstreamSuffix` maps the long community id
  to the short upstream slug; an unrecognised mode returns `""` and skips the
  fallback.

The upstream payload is a large Next.js page, not JSON. The board lives in
`<script id="__NEXT_DATA__">` at `props.pageProps.entries`. Rows are keyed
positionally: `1`=rank, `3`=name, `5`=points, `6`/`7`/`8`=platform names,
`12`=club tag, `13`=club UUID. Freshness comes from
`props.pageProps.lastUpdatedAt`; upstream sends no `age` or `last-modified`
headers.

Because upstream has no `?name=` filter, the match happens locally. Base names
genuinely collide, so `_findUpstreamRow` requires a **unique** base-name match or
a **unique** full-name match including the discriminator. It reports
`Name matches N players` rather than ever resolving to a stranger.

`boardCount` comes free from `entries.length` on the upstream path, so no
`?count=true` request is needed. A 404 that cannot be recovered still surfaces as
an HTTP error with history untouched — never a stale figure from a finished
season.

## Board IDs

`<season><mode>`, for example `s12quickcash`, `s12powershift`, `s12` (Ranked) or
`s12sponsor`. Quick Cash starts at season 5. Past seasons return where the player
finished, not how they progressed.

The board label is generated from the id; an unrecognised mode falls through to
its raw slug rather than rendering as "Ranked".

## History store

`~/.local/state/DankMaterialShell/plugins/finalsRank/history.jsonl`, one JSON
object per line, oldest first:

```json
{"t":1791825841131,"b":"s12quickcash","p":"crossplay","r":42,"k":12340}
```

The state directory is used rather than the plugin directory so the file survives
a reinstall. The path is built from
`StandardPaths.writableLocation(GenericStateLocation)`; `FileView` does not
expand `~`, so it must be absolute.

### One sample per change, not per poll

A 15-minute poll against a leaderboard that only moves when you play means most
polls are identical. Dedupe discards them at the point of recording, so the file
holds changes only. At the defaults that is a few hundred bytes a month.

### Deltas

Rank direction is inverted in the maths, not the display: a drop in rank number
is an improvement, so `rankDelta` is positive when you climb.

The baseline is the newest sample at or before `now - window`, falling back to
the oldest held sample when the window is still empty. Without that fallback the
very first movement you record would show no change at all.

Deltas only appear once the store holds two samples. A single `+0` is noise.

### Scoping and retention

Samples carry their board and platform, and every derived figure is computed only
over rows matching the current one. Switching boards therefore shows that board's
own deltas and best.

`retentionDays` (default 120) drops older samples on the next write.
`maxSamples` (20,000) is a non-user-facing backstop; retention is the dial.

### Writing

JSONL rather than one JSON array: a torn final line costs one sample instead of
the whole file. `_ingest` skips unparseable lines, so an interrupted write
degrades gracefully. Writes are serialized with `JSON.stringify`, which keeps
board and platform strings from breaking the line if a setting ever contains a
quote or newline.

There is no `FileViewSink` in Quickshell — writes go through the same `FileView`
via `setText()`, which is what `SettingsData` and `CacheData` do.

`blockLoading: true` suppresses the implicit startup read, so the read must be
requested explicitly with `historyFile.reload()` from `Component.onCompleted`.

## Percentile and past seasons

`?count=true` returns the board's entry count in a small response, so
`top 1.4% of 10,000` costs one extra request, fetched on board change rather than
every poll. Precision follows magnitude: one decimal above 1%, two below.

`pastSeasons` excludes the current board and sorts newest season first.
`careerBest` is the lowest Quick Cash rank across every season; the matching row
is tinted. The popout shows 3 rows, the desktop card 5.

Mode names come from `modeLabel()`, shared with `boardLabel`, so a mode cannot be
named one way on the board and another in the list.

## How often the API actually updates

Live boards are cached for about 10 minutes. The response carries
`cache-control`, `age` and `last-modified` headers, and `age` climbs in lock-step
with wall-clock time while `last-modified` stays frozen. Polling faster than the
cache window is wasted requests; the default 15-minute interval is already past
that floor.

`age` and `last-modified` are the honest freshness signal. The primary fetch runs
with `-D -` so headers arrive on stdout ahead of the body, and `_splitResponse()`
peels them off. The panel shows `data 4m old` rather than when the local poll
happened.

Two details the naive implementation gets wrong:

- **With `-L` there can be several header blocks**, one per redirect hop. The
  last one is the real response.
- **With `--fail` the body is discarded but the status line is still in the header
  block**, so errors must fall back to the `HTTP/2 404` line rather than the `-w`
  suffix.

The upstream fallback has no `age`/`last-modified` headers, so it reads
freshness from `props.pageProps.lastUpdatedAt`.

Archived seasons never change; their timestamps come from a single backfill run.

## Rates and staleness

- **`rankDelta` / `pointsDelta`** over a configurable window (`deltaHours`,
  default 24).
- **`pointsPerHour`** — points gained normalized by elapsed time, rendered as
  `43,800 pts/day`. It requires two samples spanning at least an hour; below that
  it returns `-1` and the row is hidden.
- **`lastUpdated`** ticks on every poll including failed ones. `lastGoodMs` is set
  only when a response carried an entry, and `isStale` fires past
  `max(30 min, 2 × refreshMinutes)`.

Every sample records the API's `age` at capture time as an optional `a` field.
This lets `meanDataAgeSec` answer "how old was this data typically when we saw
it" — a rate computed from stale reads understates the real pace of change.

Sessions-per-day are deliberately not implemented. With 15-minute polling, an
idle-threshold clustering would measure the poll schedule rather than play.

## Off board, or wrong name?

The board endpoint answers `count: 0, data: []` identically for "this player does
not exist" and "this player exists but is not on this board". They are
distinguishable via `/v1/players?q=…&exactMatch=true`, which is fired only after
an empty board response. Until it returns, the display says `off board`; after
it, `name not found` plus a `not in this board's top 10,000` note.

Switching player, board or platform clears the displayed entry immediately. The
old figure belongs to a different player or board and must not be shown as
current.

## Notifications and control centre

`Logic/` has no `qs.*` imports so it stays loadable outside DMS for testing, and
notifying is the host's job. It emits `rankMoved(previousRank, newRank, points)`
and the host decides.

A toast and a notification are different subsystems in DMS, and only the second
has a history. `ToastService` is the in-shell transient overlay; it never touches
the notification service or its history file. The plugin therefore posts a real
desktop notification with `dms notify`, using the long-form flags the installed
CLI accepts (`--app`, `--icon`, `--timeout`, `--file`). There is deliberately no
`--transient`, which would mean "do not keep this in history".

`previousRank` is only updated from a response that carried an entry, so a failed
poll cannot look like a movement from `-1`. It is cleared on a board/player/
platform switch.

The notification baseline is measured from the last **notification**, not the
last poll. `lastNotifiedRank` is updated only after a ping is sent, so one ping
reports everything since the user was last told. After a restart it falls back to
the newest history row, then to `previousRank`.

The control-centre presence uses plain `PluginComponent` properties:
`ccWidgetIcon`, `ccWidgetPrimaryText`, `ccWidgetSecondaryText`,
`ccWidgetIsActive`.

## Trend sparklines

`Logic/Sparkline.qml` draws a line with a gradient fading to the baseline and
three faint guides, normalized to its own min/max. The panel draws score above
and rank below, sharing one width so they are visually comparable.

Rank is plotted negated, so going up means a better rank. Tint follows direction
over the whole series, not just the last two points.

Three samples is the minimum. Two points draw a straight line that conveys
nothing; below three the panel shows `trend builds after 3 changes · N so far`.

The series are change events, not a uniform time series, so they are plotted in
recorded order, not against a time axis. Hover snaps to the nearest recorded
sample and shows a value tooltip. The hover `MouseArea` uses
`acceptedButtons: Qt.NoButton` so clicks still reach the host's refresh surface.

## The logo

`assets/finals-logo.png` — the game mark, bundled rather than fetched. A network
logo would leave a gap on every cold start and break if the source were down.

`FinalsLogo.qml` sizes by height and derives `implicitWidth` from the aspect, so
a non-square asset dropped in later keeps the same `size` semantics.
`sourceSize` tracks the on-screen size and `devicePixelRatio`. The error state
dims the mark rather than replacing it, and a missing file falls back to the
trophy `DankIcon`.

`source` uses `Qt.resolvedUrl`, so the path is anchored to the QML file rather
than the process working directory.

## The rank headline

The hero is one visual unit: logo, rank badge, points and the resolved player
name, then a percentile/movement row, then the charts. The rank is a large bold
badge; non-numeric states (`off board`, `name not found`) drop to a smaller size
so they fit.

The design tokens at the top of `FinalsPanel.qml` (`rankSize`, `pointsSize`,
`labelSize`, `metaSize`, `microSize`, `heroGap`, `padX`, `padY`) are the only
place sizes should be changed. The `narrow` breakpoint at `width < 290` scales the
hero down for the 240px desktop minimum rather than letting it wrap.

The refresh control is a 26×26 icon button, not a text label: `"refresh"` was the
longest word in the footer and forced the status text to elide. It swaps to
`sync` while loading, spins via `RotationAnimator`, dims while disabled, and gets
a primary border on hover.

## QML gotchas

- **Inside an inline `Component { }`, qualify nothing.** `root` does not resolve
  to the enclosing component inside `popoutContent` or `horizontalBarPill`
  bodies, so `root.someId` is `undefined` and silently returns nothing. Use the
  bare name. Rectangles keep drawing, which makes it look like a layout problem
  rather than a scope one.
- **`closePopout` is passed as `closePopoutFn()`**, a function bound in the
  enclosing scope, not as `root.closePopout`.
- **`Row.baseline` is read-only** and `Row` has no `bottomMargin`. Aligning a
  large rank against smaller text needs an `Item` with explicit anchors.
- **`StyledRect` has no padding properties** — it is a bare `Rectangle`. Use the
  Column's spacing for the air around rules.
- **A broken image path fails silently** — `Image.status` can still reach
  `Ready`. Check `status`, `sourceSize` and `paintedWidth` explicitly.
- **`qmllint` exits non-zero on failure but may print nothing.** Check the exit
  code. The import path needs a `qs` symlink to the shell root.
- **`qmlcachegen` is not usable here** — the unversioned `import Quickshell`
  fails on unmodified files too, so its errors say nothing about your changes.

## Player name resolution

The request sets `exactMatch=true`. Without it the `name` filter is a substring
match, so a short query can return thousands of entries and the widget would show
a different player. `exactMatch` still accepts a bare name and resolves it to the
full name including the discriminator.

Three outcomes are kept separate:

| Situation | Shown |
|---|---|
| No matching row | `off board` — below the top 10,000, not missing |
| More than one match | `Name matches N players — add #discriminator` |
| Returned name ≠ configured name | `Name mismatch — got <name>` |

A 404 from a bad board id reports `HTTP 404 (curl 22)` instead of parsing an
error body as leaderboard data.

## curl flags

`-L` is load-bearing: the API answers unknown query parameters with a 302 and an
empty body, so without it a future parameter addition reads as `Empty response`.
`--fail` turns 4xx/5xx into a non-zero exit rather than a body that would be
parsed as data. `-w "\n%{http_code}"` appends the status to stdout; it is split
off in `onExited` because `_parse` never runs when curl reports failure.

The upstream retry drops `-D -` because upstream returns a full HTML document;
splitting headers off stdout would eat the page. It uses a longer timeout because
the document is much larger than the community API's JSON response.

## Testing

Offline tests extract the real helpers from the shipped QML with brace matching
and run them in a `vm` sandbox:

```sh
npm test
```

They cover board/mode parsing, name matching, response splitting, the upstream
URL map, collision handling, history JSONL serialization, pruning, delta
baselines and ingestion of torn lines. They also scan the QML tree for accidental
personal defaults, absolute paths and browser-impersonating user agents.

The optional live check needs a player name:

```sh
FINALS_PLAYER='YourName#1234' npm run test:live
```

It asserts shape, not exact live values (`rank > 0`, `points` is an integer,
`resolvedName` is canonical), because ranks and points move. It also exercises
the upstream fallback when `FINALS_UPSTREAM=1` is set.

For a headless integration check, copy the Logic files into a temporary directory
and run them under `quickshell -p`. `FinalsLogic.qml` imports only `QtQuick`,
`Quickshell` and `Quickshell.Io`, so it needs no DMS modules. `FinalsPanel.qml`
needs `Theme`/`StyledText`/`DankIcon`; stub those to measure geometry offline.

## Reloading after edits

```sh
dms ipc call plugin-scan reload finalsRank
dms ipc call plugins enable finalsRank
```

The reload busts the cache for the top-level component only. If you see a stale
error for an edited file, clear `~/.cache/quickshell/qmlcache` first — Qt caches
a failed compile against the file URL and keeps replaying it.

**Edits under `Logic/` need a shell restart.** The plugin reload path does not
invalidate the engine's cached units for those files, and the failure is silent:

```sh
systemctl --user restart dms.service
```

## Release checklist

1. Run `npm test`.
2. Run `qmllint` over every `.qml` file and check the exit code.
3. Check the tree for personal data:

   ```sh
   grep -rniE '(/home|/tmp)/|Mozilla/5\.0|playerName:\s*"[^"]+"' \
     --exclude-dir=.git --exclude=LICENSE .
   ```

   The only expected hit is the author line in `plugin.json`/`LICENSE`.
4. Update `CHANGELOG.md` and the version in `plugin.json`.
5. Add a screenshot to the repository and reference it from the README and
   `plugin.json` (`"screenshot": "..."`) once one is available.
6. Commit with a clean history and push.

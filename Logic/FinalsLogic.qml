import QtQuick
import Quickshell
import Quickshell.Io
import "."

// FinalsLogic.qml — the single data layer for the finalsRank plugin.
//
// Widget.qml (bar pill + popout) and DesktopWidget.qml both instantiate this as
// `fd`, and Logic/FinalsPanel.qml renders it. There is exactly one copy of every
// calculation and of the fetch, so the two surfaces cannot drift apart.
//
// Hosted by DesktopPluginWrapper or PluginComponent, which assign these inputs.
// Defaults match plugin.json / Settings.qml so the plugin still works if a host
// forgets to bind something.

Item {
    id: fd

    // Emitted when a poll observes a different rank than the previous one.
    // The host decides whether that is worth interrupting the user for —
    // Logic/ deliberately has no qs.* imports so it stays loadable outside DMS.
    signal rankMoved(int previousRank, int newRank, int points)

    // ── Inputs (bound by the host surface) ───────────────────────────────────
    // Empty on purpose: a fresh install must never display someone else's
    // player. The host prompts the user to set one.
    property string playerName:    ""
    readonly property string playerKey: String(fd.playerName || "").trim()
    property string board:          "s12quickcash"
    property string platform:       "crossplay"
    property string seasonName:     "PRIME TIME"
    property string seasonStartIso: "2026-10-20T13:00:00Z"
    // S12's end is not announced yet. 2027-01-21 is start + 93 days, matching
    // current tracker consensus (ggseason models a 93-day season; gamestar
    // forecasts S13's start for Jan 21 2027). Note recent seasons ran 103 days
    // (S11: 2026-07-09 → 2026-10-20), so this is a consensus, not a derivation.
    // Replace it when Embark confirms the real date.
    property string seasonEndIso:   "2027-01-21T13:00:00Z"
    property bool   showPoints:     true
    property int    refreshMinutes: 15

    // ── History config (bound by the host) ───────────────────────────────────
    property bool   historyEnabled: true
    property int    retentionDays:  120
    property bool   dedupeChanges:  true
    property int    deltaHours:     24

    // Percentile ("top 1.4%") and the season-history fetch. Both add a request,
    // so both are opt-in; the live figure never depends on them.
    property bool   showPercentile: true
    property bool   showSeasons:    true
    // Sponsors boards rank by fan count, not performance, and carry no points.
    // Off by default so the season list is one comparable series.
    property bool   includeSponsors: false
    // Declared so the host can bind it; Logic/ itself does not notify,
    // it only emits rankMoved.
    property bool   toastOnRankChange: true
    // Absolute path to the JSONL file. FileView does not expand "~", so a host
    // must supply a resolved path. Empty disables persistence entirely.
    property string historyPath:    ""

    // A descriptive agent is both honest and easier for API operators to
    // identify. Avoid impersonating a browser.
    readonly property string userAgent: "finalsRank/1.3.0 (DankMaterialShell plugin)"

    // ── Live state ───────────────────────────────────────────────────────────
    property bool   loading:     false
    property bool   hasEntry:    false
    property int    rank:        -1
    property int    points:      -1
    property string lastUpdated: ""
    property string errorText:   ""

    // The full Embark name as the API resolved it, e.g. "Player#1234" from a
    // configured "player". Needed because /v1/player/{name} 404s unless it
    // gets the exact name including the discriminator, while the board endpoint
    // resolves bare names itself.
    property string resolvedName: ""

    // Data freshness, straight from the response headers. Distinct from
    // lastGoodMs, which is when *we* last received a usable answer.
    property int    dataAgeSec:        -1     // Cloudflare `age` header
    property real   dataModifiedMs:    0      // `last-modified`, parsed
    property bool   dataFreshnessKnown: false

    // Timestamp of the last response that actually carried an entry. Separate
    // from lastUpdated, which records every poll including failed ones and so
    // would otherwise imply the figure is fresh when it may be hours old.
    property real lastGoodMs: 0
    readonly property real lastGoodAgeMs: lastGoodMs > 0 ? (_now - lastGoodMs) : 0

    // Older than two refresh cycles: the number on screen may not reflect the
    // leaderboard any more.
    readonly property bool isStale:
        lastGoodMs > 0 && lastGoodAgeMs > Math.max(1800000, refreshMinutes * 60000 * 2)

    readonly property string staleText: {
        if (lastGoodMs === 0) return ""
        var mins = Math.floor(lastGoodAgeMs / 60000)
        if (mins < 60) return "last good read " + Math.max(1, mins) + "m ago"
        var hrs = Math.floor(mins / 60)
        if (hrs < 24) return "last good read " + hrs + "h " + (mins % 60) + "m ago"
        return "last good read " + Math.floor(hrs / 24) + "d ago"
    }

    // ── Data freshness, from the response headers ────────────────────────────
    // This is the API's own age for the figure on screen. Preferred over
    // lastUpdated (when we polled) and over the /v1/player updatedAt (which
    // belongs to the stale snapshot family).
    readonly property string dataAgeText: {
        if (!dataFreshnessKnown) return ""
        if (dataAgeSec < 0) return "age unknown"
        if (dataAgeSec < 60) return dataAgeSec + "s old"
        var mins = Math.floor(dataAgeSec / 60)
        if (mins < 60) return mins + "m old"
        return Math.floor(mins / 60) + "h old"
    }

    // Ages past a full cache window mean the figure could be from before the
    // last refresh entirely.
    readonly property bool dataAging: dataAgeSec > 600

    // ── Rate figures ─────────────────────────────────────────────────────────
    // Points gained per hour, normalised by elapsed time rather than compared
    // against a single baseline. Requires at least two samples spanning at
    // least an hour, otherwise any number would be noise.
    readonly property real pointsPerHour: {
        var rows = hist.scoped
        if (rows.length < 2) return -1
        var a = rows[0], b = rows[rows.length - 1]
        var hrs = (b.t - a.t) / 3600000
        if (hrs < 1) return -1
        if (b.k < 0 || a.k < 0) return -1
        return (b.k - a.k) / hrs
    }

    readonly property string rateText: {
        if (pointsPerHour < 0) return ""
        var perDay = pointsPerHour * 24
        var n = Math.round(perDay).toLocaleString(Qt.locale(), "f", 0)
        return n + " pts/day"
    }
    property real   _now:        Date.now()

    readonly property real seasonStartMs: Date.parse(seasonStartIso)
    readonly property real seasonEndMs:   Date.parse(seasonEndIso)
    readonly property bool seasonValid:   !isNaN(seasonStartMs) && !isNaN(seasonEndMs) && seasonEndMs > seasonStartMs
    readonly property real seasonLeftMs:  seasonValid ? seasonEndMs - _now : 0
    readonly property bool seasonDone:    seasonValid ? seasonLeftMs <= 0 : false
    readonly property real seasonProgress: {
        if (!seasonValid) return 0
        var t = (_now - seasonStartMs) / (seasonEndMs - seasonStartMs)
        return Math.max(0, Math.min(1, t))
    }

    // ── Derived ──────────────────────────────────────────────────────────────
    readonly property var modeNames: {
        "": "Ranked",
        "bankit": "Bank It",
        "blastoff": "Blast Off",
        "cashball": "Cashball",
        "creatorgauntlet": "Creator Gauntlet",
        "ghoulrush": "Ghoul Rush",
        "head2head": "Head 2 Head",
        "heavenorelse": "Heaven or Hell",
        "heavyhitters": "Heavy Hitters",
        "orbitalhitters": "Orbital Hitters",
        "original": "Original",
        "pointbreak": "Point Break",
        "powershift": "Power Shift",
        "quickcash": "Quick Cash",
        "sponsor": "Sponsors",
        "soloshowdown": "Solo Showdown",
        "starlighthollow": "Starlight Hollow",
        "teamdeathmatch": "Team Deathmatch",
        "terminalattack": "Terminal Attack",
        "the24hourgauntlet": "24 Hour Gauntlet",
        "worldtour": "World Tour"
    }

    // Shared by the board label and the past-season rows, so "quickcash" cannot
    // be named one way on the board and another in the list.
    function modeLabel(mode) {
        return fd.modeNames[mode] || mode || "Ranked"
    }

    readonly property string boardLabel: {
        var m = board.match(/^s(\d+)(.*)$/)
        if (!m) return board
        return modeLabel(m[2]) + " · Season " + m[1]
    }

    readonly property string pointsText: {
        if (!hasEntry || points < 0) return "—"
        return points.toLocaleString(Qt.locale(), "f", 0)
    }

    readonly property string countdownShort: {
        if (!seasonValid) return ""
        if (seasonDone) return "ended"
        var s = Math.floor(seasonLeftMs / 1000)
        var dd = Math.floor(s / 86400)
        var h = Math.floor((s % 86400) / 3600)
        if (dd > 0) return dd + "d " + h + "h"
        var m = Math.floor((s % 3600) / 60)
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    readonly property string countdownLong: {
        if (!seasonValid) return "no season dates set"
        if (seasonDone) return "season ended"
        var s = Math.max(0, Math.floor(seasonLeftMs / 1000))
        var dd = Math.floor(s / 86400)
        var h = Math.floor((s % 86400) / 3600)
        var m = Math.floor((s % 3600) / 60)
        var sec = s % 60
        var pad = function(n) { return (n < 10 ? "0" : "") + n }
        if (dd > 0) return dd + "d " + pad(h) + ":" + pad(m) + ":" + pad(sec)
        return pad(h) + ":" + pad(m) + ":" + pad(sec)
    }

    readonly property string endLabel: {
        if (!seasonValid) return "unset"
        var dt = new Date(seasonEndMs)
        var pad = function(n) { return (n < 10 ? "0" : "") + n }
        return dt.getFullYear() + "-" + pad(dt.getMonth() + 1) + "-" + pad(dt.getDate())
            + " " + pad(dt.getHours()) + ":" + pad(dt.getMinutes())
    }

    // "UTC+02" rather than the word "local". The countdown is relative so its
    // zone never matters, but this line is an absolute clock time and saying
    // only "local" leaves the reader guessing.
    readonly property string utcOffsetLabel: {
        var mins = -new Date(seasonEndMs).getTimezoneOffset()
        var sign = mins < 0 ? "-" : "+"
        var a = Math.abs(mins)
        var h = Math.floor(a / 60)
        var m = a % 60
        return "UTC" + sign + h + (m === 0 ? "" : ":" + (m < 10 ? "0" : "") + m)
    }

    // Points suffix, empty when points are hidden or absent. Bound here rather
    // than in a host, so both surfaces format it identically.
    readonly property string pointsSuffix:
        (!showPoints || !hasEntry || points < 0) ? "" : pointsText + " pts"

    // ── Season identity, derived rather than configured ──────────────────────
    // The season number is read out of the board id. `board` stays the manual
    // override for anyone tracking an archived board.
    readonly property int seasonNumber: {
        var m = board.match(/^s(\d+)/)
        return m ? parseInt(m[1]) : -1
    }

    // ── Board size / percentile ──────────────────────────────────────────────
    // `?count=true` returns 169 bytes and the board's entry count, which is the
    // denominator for a percentile. Kept separate from the entry fetch because
    // it is a different question and a much cheaper answer.
    property int    boardCount:   -1
    readonly property bool hasPercentile: boardCount > 0 && hasEntry

    // Share of the board you outrank, as a percentage. Precision follows
    // magnitude: a capped 10,000 board puts most people well under 1%.
    readonly property string percentileText: {
        if (!hasPercentile) return ""
        var pct = rank / boardCount * 100
        if (pct >= 10) return pct.toFixed(0) + "%"
        if (pct >= 1) return pct.toFixed(1) + "%"
        return pct.toFixed(2) + "%"
    }

    // "top 1.4% of 10,000"
    readonly property string percentileFull: {
        if (!hasPercentile) return ""
        return "top " + percentileText + " of "
            + boardCount.toLocaleString(Qt.locale(), "f", 0)
    }

    // ── Why is there no entry? ───────────────────────────────────────────────
    // The board endpoint answers `count: 0, data: []` identically for "this
    // player does not exist" and "this player exists but is not on this board",
    // so the two cannot be told apart from that response alone.
    //
    // They ARE distinguishable via /v1/players?exactMatch=true, which returns
    // the player across every board. That is only consulted when the board came
    // back empty, so it costs nothing in the normal case.
    property string offBoardReason: ""   // "" | "unknown-player" | "not-on-board"

    readonly property bool nameUnknown: offBoardReason === "unknown-player"

    // What to actually show. Deliberately does not claim certainty the API
    // cannot support: an empty result is "no entry here", and the reason line
    // only appears once the name has been positively checked.
    readonly property string rankText: {
        if (hasEntry) return "#" + rank
        if (loading) return "···"
        if (errorText !== "") return "—"
        if (nameUnknown) return "name not found"
        return "off board"
    }

    readonly property string offBoardNote: {
        if (hasEntry || errorText !== "") return ""
        if (nameUnknown) return "no player called " + fd.playerKey + " on this API"
        if (offBoardReason === "not-on-board")
            return "not in this board's top " + (boardCount > 0 ? boardCount.toLocaleString(Qt.locale(), "f", 0) : "10,000")
        return ""
    }

    // ── Season history ───────────────────────────────────────────────────────
    // GET /v1/player/{name} returns every board the player appears on, in one
    // 2.2KB response: past seasons and other modes, with the server's own
    // updatedAt for each.
    //
    // It is NOT used for the current board. Verified against the live feed: it
    // is a periodic snapshot and lagged the live leaderboard endpoint by ~1.5h
    // (rank 136 vs 137). The live figure always comes from the board fetch.
    // History only needs the season-final numbers, which do not move.
    property var    seasons:   []        // [{ id, season, mode, rank, points }]
    property string serverUpdated: ""     // server updatedAt of the current board
    property bool   seasonsError: false

    readonly property bool seasonsLoaded: seasons.length > 0

    // Sorted newest season first, current board excluded (that one is live).
    readonly property var pastSeasons: {
        var out = []
        for (var i = 0; i < seasons.length; i++) {
            if (seasons[i].id === board) continue
            out.push(seasons[i])
        }
        out.sort(function(a, b) {
            if (a.season !== b.season) return b.season - a.season
            return a.mode < b.mode ? -1 : 1
        })
        return out
    }

    // Best (lowest) rank across every Quick Cash season — the career high.
    readonly property int careerBest: {
        var b = -1
        for (var i = 0; i < seasons.length; i++) {
            if (seasons[i].mode !== "quickcash") continue
            if (seasons[i].rank > 0 && (b === -1 || seasons[i].rank < b)) b = seasons[i].rank
        }
        return b
    }

    // "feed updated 1h 28m ago" — how old the API's own snapshot is. Honest
    // about the fact that this is the feed's age, not the local poll's.
    readonly property string serverAgeText: {
        if (serverUpdated === "") return ""
        var then = Date.parse(serverUpdated)
        if (isNaN(then)) return ""
        var mins = Math.max(0, Math.floor((Date.now() - then) / 60000))
        if (mins < 1) return "just now"
        if (mins < 60) return mins + "m ago"
        var hrs = Math.floor(mins / 60)
        if (hrs < 24) return hrs + "h " + (mins % 60) + "m ago"
        return Math.floor(hrs / 24) + "d ago"
    }

    // Requires the resolved name, which includes the "#discriminator" the board
    // endpoint supplies. A bare configured name 404s here, so this waits for the
    // primary fetch rather than guessing.
    // Consulted only after an empty board response, so it costs nothing normally.
    // Resets rather than re-asking on every poll, because a name that does not
    // exist will not start existing between two polls an hour apart.
    property bool validatingName: false

    // Last rank that carried an entry. Board and player changes clear it so a
    // switch cannot be reported as a huge climb or fall.
    property int previousRank: 0

    function _validateName() {
        if (fd.playerKey === "" || validatingName) return
        if (offBoardReason !== "") return
        validatingName = true
        proc3.requestUrl = "https://api.the-finals-leaderboard.com/v1/players?q="
            + encodeURIComponent(fd.playerKey) + "&exactMatch=true"
        proc3.running = true
    }

    function _parseNameCheck(body) {
        validatingName = false
        if (!body || body.trim() === "") return
        var doc = null
        try {
            doc = JSON.parse(body)
        } catch (e) { return }
        if (!doc) return
        // count 0 means the API has never heard of this name; anything else
        // means the player is real and simply absent from this board.
        var n = (doc.count === undefined) ? 0 : parseInt(doc.count)
        offBoardReason = (n === 0) ? "unknown-player" : "not-on-board"
    }

    function _seasonFetch() {
        if (!showSeasons || resolvedName === "") return
        proc2.requestUrl = "https://api.the-finals-leaderboard.com/v1/player/"
            + encodeURIComponent(resolvedName)
        proc2.running = true
    }

    function _parseSeasons(body) {
        if (!body || body.trim() === "") { seasonsError = true; return }
        var doc = null
        try {
            doc = JSON.parse(body)
        } catch (e) {
            try {
                doc = JSON.parse(body.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g, ""))
            } catch (e2) { seasonsError = true; return }
        }
        if (!doc || !doc.leaderboards) { seasonsError = true; return }

        var out = []
        for (var i = 0; i < doc.leaderboards.length; i++) {
            var e = doc.leaderboards[i]
            var m = String(e.leaderboardId || "").match(/^s(\d+)([a-z0-9]*)$/)
            if (!m) continue
            out.push({
                id: e.leaderboardId,
                season: parseInt(m[1]),
                mode: m[2] === "" ? "ranked" : m[2],
                rank: (e.rank === undefined || e.rank === null) ? -1 : parseInt(e.rank),
                points: (e.points === undefined || e.points === null) ? -1 : parseInt(e.points),
                updatedAt: e.updatedAt || ""
            })
            if (e.leaderboardId === board) serverUpdated = e.updatedAt || ""
        }
        seasons = out
        seasonsError = false
    }

    // ── Upstream fallback (Embark's own feed) ───────────────────────────────
    // The community API adds new-season boards by hand, so for the first days
    // of every season it answers 404 for the current board while Embark already
    // serves it. On a 404 for a *crossplay* board we retry against
    // id.embark.games directly.
    //
    // Two constraints keep this a narrow fallback rather than a second source:
    //
    //   * Upstream is **crossplay only**. It has no platform filter (69 of 72
    //     boards accept crossplay alone), so a steam/psn/xbox board must NOT
    //     fall back — that would silently relabel crossplay figures.
    //   * Upstream only carries the **current** season's variant boards.
    //     Measured: s12qc 200, s11qc 404 (it served 200 two days earlier).
    //     Archived boards therefore stay on the community API.
    //
    // Rows are keyed by position, not name: 1=rank, 3=name, 5=points,
    // 6/7/8=steam/psn/xbox display names, 12=club tag, 13=club UUID.
    // `props.pageProps.lastUpdatedAt` (ms) is the freshness signal — upstream
    // sends no age/last-modified headers.

    // community mode suffix -> Embark slug suffix. "" is the ranked board (sN).
    readonly property var upstreamSuffix: {
        "": "", "quickcash": "qc", "powershift": "ps", "sponsor": "s",
        "worldtour": "wt", "teamdeathmatch": "tdm", "pointbreak": "pb",
        "soloshowdown": "ss", "orbitalhitters": "hh"
    }

    // "" when this board has no upstream equivalent — the normal answer for
    // archived seasons and for experimental modes Embark no longer serves.
    function _upstreamUrl(b) {
        if (String(b) === "orf")
            return "https://id.embark.games/the-finals/leaderboards/orf"
        var m = String(b).match(/^s(\d+)([a-z]*)$/)
        if (!m) return ""
        var suffix = upstreamSuffix[m[2]]
        if (suffix === undefined) return ""
        return "https://id.embark.games/the-finals/leaderboards/s" + m[1] + suffix
    }

    // Upstream has no name filter, so the match happens here — and because base
    // names DO collide (measured on one board: "nobody" ×5, "player0" ×5) a
    // loose match is exactly the wrong-player bug this plugin already shipped
    // once. Require a unique base-name match; when several collide, accept only
    // a unique full-name match including the #discriminator.
    function _findUpstreamRow(entries, want) {
        var base = _baseName(want)
        if (base === "") return { __ambiguous: 0 }
        var baseHits = [], exactHits = []
        var wl = String(want).toLowerCase()
        for (var i = 0; i < entries.length; i++) {
            var n = String(entries[i]["3"] || "")
            if (n === "" || _baseName(n) !== base) continue
            baseHits.push(entries[i])
            if (n.toLowerCase() === wl) exactHits.push(entries[i])
        }
        if (exactHits.length === 1) return exactHits[0]
        if (baseHits.length === 1) return baseHits[0]
        return { __ambiguous: baseHits.length }
    }

    function _parseUpstream(body) {
        if (!body || body.trim() === "") { errorText = "Empty upstream response"; return }

        // Upstream is a Next.js HTML page, not JSON. The board lives in the
        // __NEXT_DATA__ script tag — the same extraction the community API
        // itself performs upstream. The page is ~1.2MB, so match once and
        // discard the markup before parsing.
        var doc = null
        var raw = String(body)
        var nm = /<script id="__NEXT_DATA__"[^>]*>([\s\S]*?)<\/script>/.exec(raw)
        if (nm) {
            try {
                doc = JSON.parse(nm[1])
            } catch (e) {
                errorText = "Unexpected upstream payload"
                return
            }
        } else {
            // No tag: either an error page or a format change. Refuse rather
            // than guessing, and never fall through to regexing the board out
            // of markup — that is the wrong-player bug in a new costume.
            errorText = "Unexpected upstream response"
            return
        }

        var pp = doc && doc.props ? doc.props.pageProps : null
        var entries = pp ? pp.entries : null
        if (!entries || entries.length === 0) {
            errorText = "Upstream board has no entries"
            return
        }

        lastUpdated = _stamp(Date.now())

        var lu = pp.lastUpdatedAt
        if (typeof lu === "number" && lu > 0) {
            dataModifiedMs = lu
            dataAgeSec = Math.max(0, Math.round((Date.now() - lu) / 1000))
            dataFreshnessKnown = true
        }

        // Upstream always returns the full board, so the denominator is free —
        // no ?count=true round trip the way the community API path needs one.
        boardCount = entries.length

        var row = _findUpstreamRow(entries, fd.playerKey)
        if (row && row.__ambiguous !== undefined) {
            hasEntry = false; rank = -1; points = -1
            errorText = "Name matches " + row.__ambiguous + " players — add #discriminator"
            return
        }
        if (!row) {
            hasEntry = false; rank = -1; points = -1
            // Same reason as the community path: an empty board cannot tell
            // "wrong name" from "not on this board" on its own.
            if (offBoardReason === "") _validateName()
            return
        }

        offBoardReason = ""
        rank = parseInt(row["1"])
        points = (row["5"] === undefined || row["5"] === null) ? -1 : parseInt(row["5"])
        hasEntry = rank > 0
        lastGoodMs = Date.now()
        resolvedName = String(row["3"])

        if (hasEntry) {
            if (previousRank > 0 && previousRank !== rank)
                rankMoved(previousRank, rank, points)
            previousRank = rank
            hist.record(rank, points, dataAgeSec)
        }
        if (showSeasons && seasons.length === 0) _seasonFetch()
    }

    // Returns true when an upstream retry was started, so the caller knows the
    // error is not final yet and must not overwrite it.
    function _tryUpstream() {
        var url = _upstreamUrl(board)
        if (url === "" || platform !== "crossplay") return false
        loading = true
        proc4.requestUrl = url
        proc4.running = true
        return true
    }

    // ── Upstream fetch ───────────────────────────────────────────────────────
    // No -D -: upstream returns a full HTML document, so splitting headers off
    // stdout would eat the page. Freshness comes from lastUpdatedAt instead.
    Process {
        id: proc4
        property string requestUrl: ""
        property string buffer: ""

        stdout: StdioCollector {
            onStreamFinished: proc4.buffer = text
        }

        stderr: SplitParser {
            onRead: line => {}
        }

        onExited: code => {
            var body = proc4.buffer
            var sm = /\n(\d{3})\s*$/.exec(body)
            if (sm) body = body.substring(0, sm.index)
            proc4.buffer = ""
            loading = false
            if (code === 0) { _parseUpstream(body); return }
            if (errorText === "")
                errorText = "HTTP " + (sm ? sm[1] : "?") + " (curl " + code + ", upstream)"
        }

        // 45s rather than the primary fetch's 20s: this document is ~1.2MB of
        // HTML against the community API's few hundred bytes.
        command: ["curl", "-sL", "--fail", "--max-time", "45",
                  "-w", "\n%{http_code}",
                  "-H", "User-Agent: " + fd.userAgent, proc4.requestUrl]
    }

    // ── History ──────────────────────────────────────────────────────────────
    // Exposed flat so hosts and the panel read `fd.history.*` without knowing
    // the store exists.
    readonly property var  history:      hist
    readonly property int  rankDelta:    hist.rankDelta
    readonly property int  pointsDelta:  hist.pointsDelta
    readonly property int  rankDeltaAll: hist.rankDeltaAll
    readonly property int  bestRank:     hist.bestRank
    readonly property bool hasBest:      hist.hasBest
    readonly property int  sampleCount:  hist.scoped.length
    readonly property string deltaAge:   hist.sinceLabel
    readonly property var  samples:     hist.scoped

    // ── Chart series ─────────────────────────────────────────────────────────
    // Only *changes* are recorded, so these are event points rather than a
    // uniform time series. Points are drawn in recorded order.
    readonly property var pointsSeries: {
        var out = []
        var rows = hist.scoped
        for (var i = 0; i < rows.length; i++)
            if (rows[i].k >= 0) out.push(rows[i].k)
        return out
    }

    // Rank is inverted so that going UP on the chart means improving, matching
    // how every other rank display in the panel reads. Without this a climb
    // from #98 to #137 would draw as a fall.
    readonly property var rankSeries: {
        var out = []
        var rows = hist.scoped
        for (var i = 0; i < rows.length; i++)
            if (rows[i].r > 0) out.push(-rows[i].r)
        return out
    }

    // A 2-point "chart" is a straight line that says nothing about trend, so it
    // is not drawn. 3 is the first point count that can express a direction.
    readonly property bool canChart: pointsSeries.length >= 3

    readonly property bool rankCanChart: rankSeries.length >= 3

    // Tint follows direction of travel over the whole series, not just the last
    // two samples.
    readonly property bool pointsRising: {
        if (pointsSeries.length < 2) return false
        return pointsSeries[pointsSeries.length - 1] > pointsSeries[0]
    }

    readonly property bool rankImproving: {
        if (rankSeries.length < 2) return false
        // Series is negated, so a larger value already means a better rank.
        return rankSeries[rankSeries.length - 1] > rankSeries[0]
    }

    // "+12" climbs, "-3" slips, "" no movement in the window.
    readonly property string rankDeltaText: hist.rankDeltaText
    readonly property string pointsDeltaText: hist.pointsDeltaText

    // True once there is enough history for a movement figure to mean anything.
    readonly property bool hasDelta: hist.scoped.length >= 2 && hist.rankDelta !== 0

    // "24h" / "3d" — names the window the delta compares against.
    readonly property string deltaWindowLabel:
        deltaHours % 24 === 0 ? (deltaHours / 24) + "d" : deltaHours + "h"

    HistoryStore {
        id: hist
        playerName:     fd.playerName
        board:          fd.board
        platform:       fd.platform
        retentionDays:  fd.retentionDays
        dedupeChanges:  fd.dedupeChanges
        deltaHours:     fd.deltaHours
        filePath:       fd.historyEnabled ? fd.historyPath : ""
    }

    // ── Fetch ────────────────────────────────────────────────────────────────
    function refresh() {
        if (loading) return
        if (fd.playerKey === "") { errorText = "No player name set"; return }
        if (!/^s\d+[a-z0-9]*$|^orf$/.test(board)) {
            errorText = "Invalid board id"
            return
        }
        if (["crossplay", "steam", "psn", "xbox"].indexOf(platform) < 0) {
            errorText = "Invalid platform"
            return
        }
        loading = true
        errorText = ""
        // exactMatch=true is what keeps a loose substring from matching
        // thousands of other players. It resolves a bare configured name to
        // the full "Name#discriminator".
        proc.requestUrl = "https://api.the-finals-leaderboard.com/v1/leaderboard/"
            + board + "/" + platform
            + "?name=" + encodeURIComponent(fd.playerKey)
            + "&exactMatch=true"
        proc.running = true
    }

    // curl runs with `-D -` so the response headers arrive on stdout ahead of the
    // body. Split them apart here. With -L there can be several header blocks
    // (one per redirect hop) and the LAST one is the response we care about.
    //
    // Returns { headers: {...}, body: "...", status: "200" }.
    // `exitCode` is used only as a fallback, because with `--fail` the body is
    // discarded but the status line is still present in the header block.
    function _splitResponse(raw, exitCode) {
        var text = String(raw)

        // Status suffix, written by -w, is always last.
        var status = ""
        var sm = /\n(\d{3})\s*$/.exec(text)
        if (sm) {
            status = sm[1]
            text = text.substring(0, sm.index)
        }

        var parts = text.split(/\r?\n\r?\n/)
        var headerBlock = parts.length > 1 ? parts[parts.length - 2] : ""
        var body = parts[parts.length - 1]

        var headers = {}
        var lines = headerBlock.split(/\r?\n/)
        for (var i = 0; i < lines.length; i++) {
            var c = lines[i].indexOf(":")
            if (c > 0)
                headers[lines[i].substring(0, c).trim().toLowerCase()] =
                    lines[i].substring(c + 1).trim()
        }

        // Fall back to the status line of the final header block, which is what
        // survives when --fail aborts before the body is written.
        if (status === "") {
            var hs = /^HTTP\/[\d.]+\s+(\d{3})/.exec(headerBlock)
            if (hs) status = hs[1]
            else if (exitCode === 0) status = "200"
        }

        return { headers: headers, body: body, status: status }
    }

    function _parse(body, headers) {
        headers = headers || {}
        if (!body || body.trim() === "") { errorText = "Empty response"; return }

        // How old the API's data actually is, as opposed to when we asked.
        // `age` is seconds the cached copy has been held; it resets when
        // Cloudflare refetches, so it is the honest measure of staleness.
        var a = parseInt(headers["age"])
        dataAgeSec = isNaN(a) ? -1 : a
        var lm = headers["last-modified"]
        dataModifiedMs = lm ? Date.parse(lm) : NaN
        if (isNaN(dataModifiedMs)) dataModifiedMs = 0
        dataFreshnessKnown = !isNaN(a) || !!lm

        // The feed used to embed raw control characters in display names, which
        // is why this was regex parsing. That no longer happens — the current
        // 10,000-entry board parses with plain JSON.parse. The sanitizer below
        // is a fallback for that case only, and it keeps \t \n \r so valid JSON
        // survives.
        var doc = null
        try {
            doc = JSON.parse(body)
        } catch (e) {
            try {
                doc = JSON.parse(body.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g, ""))
            } catch (e2) {
                errorText = "Unexpected response"
                return
            }
        }
        if (!doc || !doc.data) { errorText = "Unexpected response"; return }

        lastUpdated = _stamp(Date.now())

        var entries = doc.data
        // Empty data is a legitimate "not in the top 10,000", not an error.
        if (entries.length === 0) {
            hasEntry = false
            rank = -1
            points = -1
            // Only now is it worth spending a request telling "wrong name" apart
            // from "not on this board" — the board response cannot.
            if (!validatingName) _validateName()
            return
        }
        offBoardReason = ""
        if (doc.count !== undefined && doc.count > 1) {
            errorText = "Name matches " + doc.count + " players — add #discriminator"
            hasEntry = false
            rank = -1
            points = -1
            return
        }

        var e = entries[0]
        // Final guard: the row we are about to show must be the player that was
        // asked for. Compares the base name because the configured value may
        // omit the discriminator the API always returns.
        var want = _baseName(fd.playerKey)
        if (want !== "" && _baseName(e.name || "") !== want) {
            errorText = "Name mismatch — got " + (e.name || "?")
            hasEntry = false
            rank = -1
            points = -1
            return
        }

        rank = parseInt(e.rank)
        points = (e.points === undefined || e.points === null) ? -1 : parseInt(e.points)
        hasEntry = rank > 0
        lastGoodMs = Date.now()

        // Compare against the previous good value only. A failed poll must not
        // look like a movement from -1, and a board switch resets the baseline
        // via previousRank below.
        //
        // hist.record() discards unchanged polls itself, so this fires on every
        // successful read and only the store decides what is worth keeping.
        if (hasEntry) {
            if (previousRank > 0 && previousRank !== rank)
                rankMoved(previousRank, rank, points)
            previousRank = rank
            hist.record(rank, points, dataAgeSec)
        }

        // Remember the canonical name so the season-history fetch can use it.
        if (e.name) {
            resolvedName = e.name
            if (showSeasons && seasons.length === 0) _seasonFetch()
        }
    }

    function _baseName(n) {
        return String(n).split("#")[0].trim().toLowerCase()
    }

    function _stamp(ms) {
        var dt = new Date(ms)
        var pad = function(n) { return (n < 10 ? "0" : "") + n }
        return pad(dt.getHours()) + ":" + pad(dt.getMinutes())
    }

    Process {
        id: proc

        property string requestUrl: ""
        property string buffer: ""
        property string statusCode: ""

        stdout: StdioCollector {
            onStreamFinished: proc.buffer = text
        }

        stderr: SplitParser {
            onRead: line => {
                if (line && line.trim() !== "") fd.errorText = line.trim()
            }
        }

        onExited: code => {
            fd.loading = false
            var split = fd._splitResponse(proc.buffer, code)
            proc.buffer = ""

            var headers = split.headers
            proc.statusCode = split.status

            if (code === 0) { fd._parse(split.body, headers); return }

            // 404 on a crossplay board is the season rollover: the community
            // API has not added the new board yet but Embark already serves it.
            // Retry upstream before reporting an error — _tryUpstream returns
            // false when there is nothing to retry (archived board, or a
            // platform upstream cannot supply), in which case fall through.
            if (proc.statusCode === "404" && fd._tryUpstream()) return

            if (fd.errorText === "")
                fd.errorText = "HTTP " + (proc.statusCode === "" ? "?" : proc.statusCode)
                    + " (curl " + code + ")"
        }

        // -L: the API 302s unknown query params and returns an EMPTY body, so
        //    without it a param change silently reads as "Empty response".
        // --fail: turns HTTP 4xx/5xx into a non-zero exit instead of a body that
        //    would be parsed as if it were leaderboard data.
        // -w writes the status code so the error message can name it.
        command: ["curl", "-sL", "--fail", "--retry", "2",
                  "--connect-timeout", "10", "--max-time", "20",
                  "-D", "-", "-w", "\n%{http_code}",
                  "-H", "User-Agent: " + fd.userAgent, proc.requestUrl]
    }

    Timer {
        interval: Math.max(300000, fd.refreshMinutes * 60000)
        repeat: true
        running: true
        onTriggered: fd.refresh()
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: fd._now = Date.now()
    }

    Timer {
        id: debounce
        interval: 800
        repeat: false
        onTriggered: fd.refresh()
    }

    // ── Secondary fetch: board size ──────────────────────────────────────────
    // Separate process so a slow or failing count request cannot delay or break
    // the entry fetch that everything else depends on.
    Process {
        id: proc1
        property string requestUrl: ""
        property string buffer: ""

        stdout: StdioCollector {
            onStreamFinished: proc1.buffer = text
        }

        stderr: SplitParser {
            onRead: line => {}
        }

        onExited: code => {
            var body = proc1.buffer
            var sm = /\n(\d{3})\s*$/.exec(body)
            if (sm) body = body.substring(0, sm.index)
            proc1.buffer = ""
            if (code !== 0 || !body || body.trim() === "") { boardCount = -1; return }
            try {
                var doc = JSON.parse(body)
                boardCount = (doc.count === undefined) ? -1 : parseInt(doc.count)
            } catch (e) {
                boardCount = -1
            }
        }

        command: ["curl", "-sL", "--fail", "--max-time", "20",
                  "-w", "\n%{http_code}",
                  "-H", "User-Agent: " + fd.userAgent, proc1.requestUrl]
    }

    // ── Name validation ──────────────────────────────────────────────────────
    // Third-tier, fired only when the board returns nothing.
    Process {
        id: proc3
        property string requestUrl: ""
        property string buffer: ""

        stdout: StdioCollector {
            onStreamFinished: proc3.buffer = text
        }

        stderr: SplitParser {
            onRead: line => {}
        }

        onExited: code => {
            var body = proc3.buffer
            var sm = /\n(\d{3})\s*$/.exec(body)
            if (sm) body = body.substring(0, sm.index)
            proc3.buffer = ""
            if (code !== 0) { fd.validatingName = false; return }
            fd._parseNameCheck(body)
        }

        command: ["curl", "-sL", "--fail", "--max-time", "20",
                  "-w", "\n%{http_code}",
                  "-H", "User-Agent: " + fd.userAgent, proc3.requestUrl]
    }

    // ── Tertiary fetch: season history ───────────────────────────────────────
    Process {
        id: proc2
        property string requestUrl: ""
        property string buffer: ""

        stdout: StdioCollector {
            onStreamFinished: proc2.buffer = text
        }

        stderr: SplitParser {
            onRead: line => {}
        }

        onExited: code => {
            var body = proc2.buffer
            var sm = /\n(\d{3})\s*$/.exec(body)
            if (sm) body = body.substring(0, sm.index)
            proc2.buffer = ""
            if (code === 0) fd._parseSeasons(body)
            else fd.seasonsError = true
        }

        command: ["curl", "-sL", "--fail", "--max-time", "20",
                  "-w", "\n%{http_code}",
                  "-H", "User-Agent: " + fd.userAgent, proc2.requestUrl]
    }

    // The board size only changes when the board does, so it is fetched on
    // demand rather than every poll.
    function refreshCount() {
        if (showPercentile && fd.playerKey !== ""
            && /^s\d+[a-z0-9]*$|^orf$/.test(board)
            && ["crossplay", "steam", "psn", "xbox"].indexOf(platform) >= 0) {
            proc1.requestUrl = "https://api.the-finals-leaderboard.com/v1/leaderboard/"
                + board + "/" + platform + "?count=true"
            proc1.running = true
        }
    }

    // Clearing the displayed entry on a name/board switch matters: until the new
    // poll lands, the old figure belongs to a different player or board and
    // would otherwise be shown as though it were current.
    function _resetForSwitch() {
        resolvedName = ""
        seasons = []
        previousRank = 0
        offBoardReason = ""
        hasEntry = false
        rank = -1
        points = -1
        errorText = ""
    }

    onPlayerNameChanged: { _resetForSwitch(); refreshCount(); debounce.restart() }
    onBoardChanged:       { _resetForSwitch(); boardCount = -1; refreshCount(); debounce.restart() }
    onPlatformChanged:    { _resetForSwitch(); boardCount = -1; refreshCount(); debounce.restart() }
    onShowPercentileChanged: if (showPercentile) refreshCount()
    onShowSeasonsChanged:    _seasonFetch()

    Component.onCompleted: {
        refresh()
        refreshCount()
    }
}
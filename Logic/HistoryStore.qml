import QtQuick
import Quickshell
import Quickshell.Io

// HistoryStore.qml — change-logged rank/points history, persisted as JSONL.
//
// One sample per *change*, not per poll. A 15-minute poll against a leaderboard
// that only moves when you play means most polls are identical, so logging each
// one would be mostly noise. Dedupe means the file stays small and the derived
// deltas are meaningful.
//
// Format is one JSON object per line, oldest first:
//   {"t":1760000000000,"b":"s11quickcash","p":"crossplay","r":137,"k":213070}
//
// Deliberately a plain file with no import of qs.* — that keeps it loadable
// outside DMS for testing, and it means the history survives a plugin reinstall
// that wipes the plugin directory.

Item {
    id: store

    // ── Config ───────────────────────────────────────────────────────────────
    property string playerName:  ""
    property string board:        ""
    property string platform:     ""

    // 0 keeps everything. Defaults to 120 days, which covers a THE FINALS
    // season (93–103 days: S11 ran 2026-07-09 → 2026-10-20 = 103 days; S12
    // 2026-10-20 → 2027-01-21 est. = 93 days) plus overlap.
    property int retentionDays:   120
    property bool dedupeChanges:  true

    // Backstop so a long history cannot grow without bound. Not user-facing —
    // retentionDays is the dial. Placed well above any realistic number of
    // *changes*: a 120-day season with a change every 20 minutes is ~8,600.
    readonly property int maxSamples: 20000

    property string filePath: ""

    // ── State ────────────────────────────────────────────────────────────────
    property var  samples: []          // parsed rows, oldest first
    property bool loaded:      false
    property string loadError:  ""
    property int  writeCount:   0

    readonly property bool ready: filePath !== "" && loaded

    // ── Derived ──────────────────────────────────────────────────────────────
    // Only samples for the currently watched board/platform count. A history
    // file accumulates several boards over time as the season rolls over.
    readonly property var scoped: {
        if (samples.length === 0) return []
        var out = []
        for (var i = 0; i < samples.length; i++) {
            var s = samples[i]
            if (board !== "" && s.b !== board) continue
            if (platform !== "" && s.p !== platform) continue
            out.push(s)
        }
        return out
    }

    readonly property var latest: scoped.length ? scoped[scoped.length - 1] : null
    readonly property var first:  scoped.length ? scoped[0] : null

    // Best (lowest) rank seen for this board — the season's high-water mark.
    readonly property int bestRank: {
        if (scoped.length === 0) return -1
        var b = Infinity
        for (var i = 0; i < scoped.length; i++) {
            var r = scoped[i].r
            if (typeof r === "number" && r > 0 && r < b) b = r
        }
        return isFinite(b) ? b : -1
    }

    readonly property bool hasBest: bestRank > 0 && latest !== null && latest.r !== bestRank

    // ── Lookups ──────────────────────────────────────────────────────────────
    // Nearest sample at or before `ms`; used for "since <time>" comparisons.
    function _atOrBefore(ms) {
        var best = null
        for (var i = 0; i < scoped.length; i++) {
            if (scoped[i].t <= ms) best = scoped[i]
            else break
        }
        return best
    }

    function _after(ms) {
        var out = []
        for (var i = 0; i < scoped.length; i++)
            if (scoped[i].t > ms) out.push(scoped[i])
        return out
    }

    // ── Deltas ───────────────────────────────────────────────────────────────
    // Rank moves are inverted: a drop in rank number is an improvement, so the
    // returned value is positive when you climbed.
    // Deltas compare against the newest sample at or before the window start.
    // If there is none — which is the normal state for the first day of
    // tracking, and whenever the window is shorter than the gap between polls
    // — fall back to the oldest sample we hold. Without that fallback the very
    // first movement you ever record would show no change at all.
    function _baseline() {
        var then = _atOrBefore(_now - windowMs)
        if (then !== null) return then
        return scoped.length ? scoped[0] : null
    }

    readonly property int rankDelta: {
        if (latest === null) return 0
        var then = _baseline()
        if (then === null || then === latest) return 0
        return then.r - latest.r
    }

    readonly property int pointsDelta: {
        if (latest === null) return 0
        var then = _baseline()
        if (then === null || then === latest) return 0
        return latest.k - then.k
    }

    // Over the whole tracked history for this board.
    readonly property int rankDeltaAll: {
        if (latest === null || first === null) return 0
        return first.r - latest.r
    }

    property real _now: Date.now()

    // Which window the "since" delta compares against. 24h is the useful
    // default; the API has no history of its own, so this is all local.
    property int deltaHours: 24
    readonly property real windowMs: deltaHours * 3600000

    readonly property string sinceLabel: {
        if (scoped.length < 2) return ""
        var firstT = first.t
        var days = Math.floor((latest.t - firstT) / 86400000)
        if (days >= 1) return days + "d"
        var hrs = Math.floor((latest.t - firstT) / 3600000)
        if (hrs >= 1) return hrs + "h"
        return Math.max(1, Math.floor((latest.t - firstT) / 60000)) + "m"
    }

    // "+12" / "-3" / "" — sign is already inverted for rank.
    function _signed(n) {
        if (n === 0) return ""
        return (n > 0 ? "+" : "") + n
    }

    readonly property string rankDeltaText: _signed(rankDelta)
    readonly property string pointsDeltaText: {
        if (pointsDelta === 0) return ""
        var n = pointsDelta
        return (n > 0 ? "+" : "") + n.toLocaleString(Qt.locale(), "f", 0)
    }

    // ── Persistence ──────────────────────────────────────────────────────────
    // blockLoading suppresses the implicit startup read, so the read has to be
    // asked for explicitly — the same thing Common/SettingsData does with a
    // debounce that calls settingsFile.reload(). Without this the store never
    // ingests an existing file and `loaded` stays false forever.
    function load() {
        if (filePath === "") { loaded = true; return }
        historyFile.reload()
    }

    // Append a sample if it represents a change. Returns true when written.
    // `dataAgeSec` is the API's own `age` header at capture time: how stale the
    // figure already was when we recorded it. -1 when the header was absent.
    function record(rank, points, dataAgeSec) {
        if (filePath === "" || !(rank > 0)) return false

        if (dedupeChanges && scoped.length) {
            var prev = scoped[scoped.length - 1]
            if (prev.r === rank && prev.k === points) return false
        }

        var row = { t: Date.now(), b: board, p: platform, r: rank, k: points }
        if (dataAgeSec !== undefined && dataAgeSec >= 0) row.a = dataAgeSec
        var next = samples.concat([row])
        next = _prune(next)
        samples = next
        _flush()
        return true
    }

    // Average staleness of the recorded samples, in seconds. Answers "how old
    // was this data typically when we saw it" — the honest counterpart to a
    // rate figure, because a rate computed from stale reads understates the
    // real pace of change.
    readonly property real meanDataAgeSec: {
        var n = 0, sum = 0
        for (var i = 0; i < scoped.length; i++) {
            if (typeof scoped[i].a === "number" && scoped[i].a >= 0) { sum += scoped[i].a; n++ }
        }
        return n > 0 ? sum / n : -1
    }

    // Retention is by age, with a hard count cap as a backstop.
    function _prune(list) {
        var out = list
        if (retentionDays > 0) {
            var cutoff = Date.now() - retentionDays * 86400000
            out = []
            for (var i = 0; i < list.length; i++)
                if (list[i].t >= cutoff) out.push(list[i])
        }
        if (out.length > maxSamples)
            out = out.slice(out.length - maxSamples)
        return out
    }

    // JSONL rather than one big JSON array: appending costs one line rewrite
    // instead of re-encoding the whole document, and a truncated final line
    // costs one sample rather than the entire file.
    function _serialize() {
        var out = []
        for (var i = 0; i < samples.length; i++) {
            var s = samples[i]
            // JSON.stringify keeps board/platform strings from breaking the
            // line if a setting ever contains a quote or newline.
            var row = { t: s.t, b: s.b, p: s.p, r: s.r, k: s.k }
            if (typeof s.a === "number") row.a = s.a
            out.push(JSON.stringify(row))
        }
        return out.join("\n") + (out.length ? "\n" : "")
    }

    function _flush() {
        historyFile.setText(_serialize())
        loadError = ""
        writeCount++
    }

    function clear() {
        samples = []
        _flush()
    }

    // ── File IO ──────────────────────────────────────────────────────────────
    // One FileView for both directions: reads come from the loaded text, writes
    // go through setText(). There is no separate sink type — FileViewSink does
    // not exist in Quickshell. This is the same pattern SettingsData and
    // CacheData use.
    FileView {
        id: historyFile
        path: store.filePath
        atomicWrites: true
        // We are the only writer, so do not reload behind our back.
        blockLoading: true
        blockWrites: false

        onLoaded: store._ingest(text())
        onLoadFailed: {
            // A missing file is the normal first-run state, not an error:
            // mark the store loaded so it can start recording.
            store.loadError = "No history yet"
            store.loaded = true
        }
    }

    // Ticks the delta window so "since 24h" stays live between polls, without
    // needing a write. Matches the clock cadence FinalsLogic already uses.
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: store._now = Date.now()
    }

    Component.onCompleted: load()

    function _ingest(raw) {
        var parsed = []
        var lines = String(raw).split("\n")
        for (var i = 0; i < lines.length; i++) {
            var ln = lines[i].trim()
            if (ln === "") continue
            try {
                var o = JSON.parse(ln)
                if (o && typeof o.t === "number" && typeof o.r === "number")
                    parsed.push(o)
            } catch (e) {
                // A torn final line from an interrupted write: skip it rather
                // than discard the whole history.
            }
        }
        samples = parsed
        loaded = true
        loadError = ""
    }
}
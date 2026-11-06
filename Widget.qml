import QtQuick
import Quickshell
import QtCore
import qs.Common
import qs.Widgets
import qs.Services
import qs.Modules.Plugins
import "./Logic"

// Widget.qml — DankBar pill and popout.
//
// All data and layout live in Logic/, shared with DesktopWidget.qml, so the
// popout and the desktop card always show identical figures. This file only
// binds settings and hosts the two bar pills.

PluginComponent {
    id: wiz

    layerNamespacePlugin: "finalsRank"

    FinalsLogic {
        id: fd

        playerName:    (wiz.pluginData.playerName || "").trim()
        board:          (wiz.pluginData.board || "s12quickcash").trim()
        platform:       (wiz.pluginData.platform || "crossplay").trim()
        seasonName:     wiz.pluginData.seasonName || "PRIME TIME"
        seasonStartIso: (wiz.pluginData.seasonStartIso || "2026-10-20T13:00:00Z").trim()
        seasonEndIso:   (wiz.pluginData.seasonEndIso || "2027-01-21T13:00:00Z").trim()
        showPoints:     wiz.pluginData.showPoints !== false

        historyEnabled: wiz.pluginData.historyEnabled !== false
        showPercentile: wiz.pluginData.showPercentile !== false
        showSeasons:    wiz.pluginData.showSeasons !== false
        includeSponsors: wiz.pluginData.includeSponsors === true
        retentionDays: {
            var n = parseInt(wiz.pluginData.retentionDays)
            // 0 means keep everything; otherwise a season-or-more default.
            if (isNaN(n) || n < 0) return 120
            return Math.min(730, n)
        }
        dedupeChanges: wiz.pluginData.dedupeChanges !== false
        toastOnRankChange: wiz.pluginData.toastOnRankChange !== false
        deltaHours: {
            var n = parseInt(wiz.pluginData.deltaHours)
            return isNaN(n) ? 24 : Math.max(1, Math.min(720, n))
        }
        historyPath: wiz.historyPath

        // Logic/ has no qs.* imports so it stays loadable outside DMS, and it
        // has no business posting notifications at all. It raises a signal and
        // the host decides whether that is worth interrupting for.
        onRankMoved: function(previousRank, newRank, points) {
            if (!fd.toastOnRankChange) return
            // Measured from the last *notification*, not the last poll, so a
            // ping says everything that happened while the user was last not
            // told rather than only the latest slice of it. previousRank is
            // only the fallback: Logic/ advances it on every good poll whether
            // or not a ping was sent, which is the wrong baseline whenever
            // notifications were off.
            var from = wiz.lastNotifiedRank > 0
                     ? wiz.lastNotifiedRank
                     : wiz._historyRank() || previousRank
            wiz.lastNotifiedRank = newRank

            var where
            if (from <= 0 || from === newRank) {
                where = "Now #" + newRank
            } else {
                var moved = from - newRank
                var n = Math.abs(moved)
                where = (moved > 0 ? "▲ Moved up " : "▼ Moved down ") + n
                      + (n === 1 ? " rank from #" : " ranks from #")
                      + from + " to #" + newRank
            }
            // ToastService is only DMS's toast *overlay* — a transient banner
            // with no history, so a rank ping through it never appears in the
            // notification centre. `dms notify` posts a real D-Bus notification
            // to DMS's own notification server, which is what lands it in
            // notification history (verified: it appears in
            // ~/.cache/DankMaterialShell/notification_history.json) and keeps
            // it until it is dismissed.
            //
            // Flags are the long forms the installed `dms` actually accepts:
            // `-a`/`-i` shorthands and --category/-u only exist in newer DMS
            // builds. There is deliberately no --transient — that flag means
            // "do not keep this in history".
            Quickshell.execDetached(["dms", "notify",
                                     "--app", "THE FINALS",
                                     "--icon", "emoji_events",
                                     "THE FINALS · " + fd.boardLabel, where])
        }

        refreshMinutes: {
            var n = parseInt(wiz.pluginData.refreshMinutes)
            return isNaN(n) ? 15 : Math.max(5, Math.min(180, n))
        }
    }

    // Rank at the time of the last notification actually sent. 0 means
    // "nothing has been notified yet", which falls back to the history store so
    // the first ping after a shell restart still has a real starting point.
    property int lastNotifiedRank: 0

    // Most recent rank the history store holds for the board/platform in play.
    // The store only records *changes*, so this is the rank as of the last
    // recorded change — the closest durable stand-in for "what the user was
    // last told" across a restart.
    function _historyRank() {
        var rows = fd.samples
        if (!rows || rows.length === 0) return 0
        var r = rows[rows.length - 1].r
        return (typeof r === "number" && r > 0) ? r : 0
    }

    // A board/player/platform switch makes the stored baseline meaningless, and
    // Logic/ clears its own previousRank at the same moment. Without this the
    // first ping on a new board would read as a huge climb or fall.
    Connections {
        target: fd
        function onPlayerNameChanged() { wiz.lastNotifiedRank = 0 }
        function onBoardChanged()       { wiz.lastNotifiedRank = 0 }
        function onPlatformChanged()    { wiz.lastNotifiedRank = 0 }
    }

    // FileView does not expand "~", so the path has to be built from an absolute
    // XDG state location — the same construction Common/AppUsageHistoryData and
    // Common/SessionData use. State rather than config: history is not a
    // preference and should outlive a plugin reinstall.
    readonly property string historyPath:
        StandardPaths.writableLocation(StandardPaths.GenericStateLocation)
        + "/DankMaterialShell/plugins/finalsRank/history.jsonl"

    readonly property color accent: fd.errorText !== "" ? Theme.warning
        : (fd.hasEntry ? Theme.primary : Theme.surfaceVariantText)

    readonly property string barText: {
        if (fd.playerKey === "") return "set player"
        if (!fd.hasEntry && fd.loading && fd.errorText === "") return "···"
        var s = fd.rankText
        if (wiz.pluginData.showCountdown !== false && fd.countdownShort !== "")
            s += " · " + fd.countdownShort
        return s
    }

    // ── Bar pill ──────────────────────────────────────────────────────────────
    horizontalBarPill: Component {
        Item {
            implicitWidth: inner.implicitWidth + Theme.spacingS * 2
            implicitHeight: inner.implicitHeight + 4

            Row {
                id: inner
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                FinalsLogo {
                    // Keeps the mark at the same size as the card and the
                    // other DMS bar pills.
                    size: Math.max(14, wiz.iconSize - 6)
                    errored: fd.errorText !== ""
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: wiz.barText
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: wiz.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: inner.implicitWidth + Theme.spacingXS * 2
            implicitHeight: inner.implicitHeight + 4

            Column {
                id: inner
                anchors.centerIn: parent
                spacing: 2

                FinalsLogo {
                    size: Math.max(14, wiz.iconSize - 6)
                    errored: fd.errorText !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: fd.hasEntry ? fd.rank : "--"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: wiz.accent
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    // ── Control centre ───────────────────────────────────────────────────────
    // finalsRank had no control-centre presence at all. These are plain
    // properties on PluginComponent; the host renders them.
    ccWidgetIcon: fd.errorText !== "" ? "cloud_off" : "emoji_events"
    ccWidgetPrimaryText: fd.hasEntry ? fd.rankText : (fd.loading ? "···" : "—")
    ccWidgetSecondaryText: fd.hasPercentile ? fd.percentileFull : fd.boardLabel
    ccWidgetIsToggle: false
    ccWidgetIsActive: fd.hasEntry

    // ── Popout ────────────────────────────────────────────────────────────────
    popoutWidth: 320
    // FinalsPanel now measures ~344px with the hero badge, rules, taller
    // interactive charts and three Quick Cash rows. 416 leaves ~70px for the
    // popout header and padding, with slack for font metrics. Bump this together
    // with DesktopWidget's minHeight/defaultHeight when adding rows or chart
    // height.
    popoutHeight: 416

    popoutContent: Component {
        PopoutComponent {
            headerText: "THE FINALS"
            detailsText: fd.boardLabel
            showCloseButton: true
            closePopout: closePopoutFn

            FinalsPanel {
                width: parent.width
                logic: fd
                onRefreshRequested: logic.refresh()
            }
        }
    }

    // Inside an inline Component, root.closePopout does not resolve, so hand the
    // popout a function bound in the enclosing scope instead.
    function closePopoutFn() {
        closePopout()
    }
}
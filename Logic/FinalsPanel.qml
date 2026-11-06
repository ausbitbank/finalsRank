import QtQuick
import qs.Common
import qs.Widgets
import "."

// FinalsPanel.qml — the one layout, rendered identically by the bar popout and
// the desktop widget. Both hosts pass the same FinalsLogic instance as `logic`,
// so the two surfaces cannot show different figures.
//
// Sized by width: it fills whatever the host gives it and lets the Column set
// the height.
//
// implicitHeight matters. An Item defaults its height to implicitHeight, and a
// bare Item would leave that at zero — the bar popout sizes its content from the
// top down, so without this the panel collapses and only the popout's own header
// is left on screen.
//
// The property is named `logic`, not `fd`: a property whose name matches the id
// of the object passed to it resolved to null inside an inline Component, which
// made every label render with an empty value and reported no error at all.
//
// Visual language: one rank hero, one movement pill, one trend block, then
// progressively quieter secondary rows. The type and spacing scales below are
// the only place sizes should be changed — every row reads from them.

Item {
    id: panel

    implicitHeight: col.implicitHeight + panel.padY * 2

    property var  logic: null
    signal refreshRequested()

    // The desktop card has room for two more past-season rows than the popout.
    // Set by the desktop host.
    property bool desktopChrome: false

    // ── Design tokens ────────────────────────────────────────────────────────
    // A small, deliberate scale rather than ad-hoc pixel sizes. Keeping these
    // here is what makes the hero / label / meta hierarchy consistent instead
    // of drifting row by row.
    readonly property real gutter: 4
    readonly property real padX: gutter
    readonly property real padY: 2

    // The card can be squeezed to 240px on the desktop. Rather than letting the
    // hero wrap into three lines, the hero scales down as one unit.
    readonly property bool narrow: width < 290
    readonly property real rankSize: narrow ? 28 : 32
    readonly property real rankSizeCompact: narrow ? 18 : 20
    readonly property real pointsSize: narrow ? 14 : 15
    readonly property real bodySize: Theme.fontSizeSmall
    readonly property real labelSize: Theme.fontSizeSmall - 1
    readonly property real metaSize: Theme.fontSizeSmall - 2
    readonly property real microSize: Theme.fontSizeSmall - 3

    readonly property real heroGap: narrow ? 8 : 10
    readonly property real rowGap: 6

    // Rank number starts at this x; the charts share it so the trend lines sit
    // directly under the figure they describe. The label gutter to its left is
    // exactly wide enough to hold "score"/"rank", keeping the plot's left edge
    // aligned with the rank number rather than the panel edge.
    readonly property real heroLogoSize: narrow ? 22 : 26
    readonly property real rankIndent: panel.heroLogoSize + panel.heroGap
    readonly property real chartGap: narrow ? 4 : Theme.spacingS
    readonly property real chartLabelWidth: Math.max(20, panel.rankIndent - panel.chartGap)

    // Secondary text is dimmed relative to the hero rather than being pure
    // white at a smaller size — size alone was not enough to stop the season
    // list and footer competing with the live rank.
    readonly property color mutedText:
        Qt.rgba(Theme.surfaceVariantText.r, Theme.surfaceVariantText.g,
                Theme.surfaceVariantText.b, 0.86)
    readonly property color faintText:
        Qt.rgba(Theme.surfaceVariantText.r, Theme.surfaceVariantText.g,
                Theme.surfaceVariantText.b, 0.78)

    // How many past-season rows to show. The popout is tight; the card has room.
    readonly property int seasonsShown: desktopChrome ? 5 : 3

    // Sponsors boards are ranked by fan count, not performance, and carry no
    // points. Interleaved with Quick Cash rows they read as one progression and
    // are simply not comparable — so they are filtered out of the list. Set
    // includeSponsors to true to see them anyway.
    readonly property var shownSeasons: {
        if (logic === null) return []
        var src = logic.pastSeasons
        if (!logic.includeSponsors) {
            var keep = []
            for (var i = 0; i < src.length; i++)
                if (src[i].mode !== "sponsor") keep.push(src[i])
            src = keep
        }
        return src.slice(0, panel.seasonsShown)
    }

    // True only when the best actually differs from the headline, which is the
    // only case where "best on this board" tells you anything new.
    readonly property bool bestIsDistinct:
        logic !== null && logic.bestRank > 0 && logic.hasBest

    // ── Movement ─────────────────────────────────────────────────────────────
    // A movement figure is worth showing when either half moved. The old
    // condition required a rank change, so a points-only gain disappeared even
    // though it is the more common movement.
    readonly property bool hasMovement:
        logic !== null && logic.sampleCount >= 2
        && (logic.rankDelta !== 0 || logic.pointsDelta !== 0)

    // Direction colour follows the rank when there is one, otherwise points.
    readonly property color movementColor: {
        if (logic === null) return Theme.surfaceVariantText
        var sign = logic.rankDelta !== 0 ? logic.rankDelta : logic.pointsDelta
        if (sign > 0) return Theme.success
        if (sign < 0) return Theme.error
        return Theme.surfaceVariantText
    }

    // "▲4 · +4,930" — compact enough for a pill, no repeated "places" wording.
    readonly property string movementMain: {
        if (logic === null || !panel.hasMovement) return ""
        var parts = []
        if (logic.rankDelta !== 0)
            parts.push((logic.rankDelta > 0 ? "▲" : "▼") + Math.abs(logic.rankDelta))
        if (logic.pointsDelta !== 0)
            parts.push((logic.pointsDelta > 0 ? "+" : "−")
                       + Math.abs(logic.pointsDelta).toLocaleString(Qt.locale(), "f", 0))
        return parts.join("  ·  ")
    }

    // Trend tints. Score rising is good; rank improving is good — the rank series
    // is already negated upstream so both use the same "up is green" rule.
    readonly property color scoreTrendColor: {
        if (logic === null || !logic.canChart) return Theme.surfaceVariantText
        if (logic.pointsRising) return Theme.success
        if (logic.pointsSeries[logic.pointsSeries.length - 1]
            < logic.pointsSeries[0]) return Theme.error
        return Theme.surfaceVariantText
    }

    readonly property color rankTrendColor: {
        if (logic === null || !logic.rankCanChart) return Theme.surfaceVariantText
        if (logic.rankImproving) return Theme.success
        if (logic.rankSeries[logic.rankSeries.length - 1]
            < logic.rankSeries[0]) return Theme.error
        return Theme.surfaceVariantText
    }

    readonly property color accent: logic === null ? Theme.surfaceVariantText
        : (logic.errorText !== "" ? Theme.warning
        : (logic.hasEntry ? Theme.primary : Theme.surfaceVariantText))

    readonly property bool heroNumeric: logic !== null && logic.hasEntry

    // At narrow widths "of 10,000" is the first thing to lose; the percentage
    // alone still answers the question the line is there for.
    readonly property string percentileText: {
        if (logic === null || !logic.hasPercentile) return ""
        return panel.narrow ? ("top " + logic.percentileText) : logic.percentileFull
    }

    // "live" only within the API's own 10-minute cache window; after that the
    // figure is still perfectly usable, it is just a synced snapshot. The dot
    // stays green unless the fetch is failing or the read is genuinely stale —
    // a routine 12-minute-old figure is not an error state.
    readonly property bool isLive:
        logic !== null && logic.hasEntry && logic.errorText === "" && !logic.isStale

    readonly property bool isFresh:
        panel.isLive && logic.dataFreshnessKnown
        && logic.dataAgeSec >= 0 && logic.dataAgeSec < 600

    readonly property color liveColor:
        logic === null ? Theme.surfaceVariantText
        : (logic.errorText !== "" || logic.isStale ? Theme.warning
        : (logic.hasEntry ? Theme.success : Theme.surfaceVariantText))

    readonly property string statusText: {
        if (logic === null) return ""
        if (logic.errorText !== "") return logic.errorText
        var s = ""
        if (logic.dataFreshnessKnown) {
            var prefix = panel.isFresh ? "live" : "synced"
            s = (panel.narrow ? "" : prefix + " · ") + "data " + logic.dataAgeText
        } else if (logic.lastUpdated === "") {
            s = "not fetched yet"
        } else {
            s = "updated " + logic.lastUpdated
        }
        if (logic.rateText !== "") s += "   ·   " + logic.rateText
        if (panel.shownSeasons.length === 0 && logic.serverAgeText !== "")
            s += "   ·   feed " + logic.serverAgeText
        return s
    }

    // The progress bar cannot show a number by itself; the percentage sits at
    // the right of the deadline line so it survives when the exact date elides
    // on a narrow card.
    readonly property string seasonEndText: {
        if (logic === null) return ""
        return (panel.narrow ? "ends " : "season ends ")
            + logic.endLabel + (panel.narrow ? "" : " " + logic.utcOffsetLabel)
    }

    readonly property string seasonElapsedText:
        logic !== null && logic.seasonValid
            ? Math.round(logic.seasonProgress * 100) + "% elapsed" : ""

    // Feed age is the first thing to drop when the card is squeezed: career
    // best is a player fact, the feed snapshot is bookkeeping.
    readonly property string seasonsMetaText: {
        if (logic === null) return ""
        var parts = []
        if (logic.careerBest > 0) parts.push("career best #" + logic.careerBest)
        if (!panel.narrow && logic.serverAgeText !== "")
            parts.push("feed " + logic.serverAgeText)
        return parts.join("   ·   ")
    }

    // A 1px hairline. Same shape as the other DMS cards' rules so they divide
    // their sections identically. Note StyledRect has no padding properties
    // (DankCommon/Widgets/StyledRect.qml is a bare Rectangle), which is why the
    // air around each rule comes from the Column's spacing instead.
    component Rule: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g,
                       Theme.surfaceVariant.b, 0.72)
    }

    // The latest value formatted for a chart tooltip. Built here so Sparkline
    // never needs to know what the numbers mean.
    readonly property var pointsTooltip: {
        if (logic === null) return []
        var out = []
        for (var i = 0; i < logic.pointsSeries.length; i++)
            out.push(logic.pointsSeries[i].toLocaleString(Qt.locale(), "f", 0) + " pts")
        return out
    }

    readonly property var rankTooltip: {
        if (logic === null) return []
        var out = []
        for (var i = 0; i < logic.rankSeries.length; i++)
            out.push("#" + Math.abs(logic.rankSeries[i]))
        return out
    }

    // Entrance is a short fade-and-lift rather than a hard swap. The popout's
    // own open/close animation belongs to DMS; this only softens the panel
    // appearing inside it.
    property bool _entered: false
    Component.onCompleted: _entered = true

    Column {
        id: col
        x: panel.padX
        y: panel.padY + (panel._entered ? 0 : 6)
        width: Math.max(0, panel.width - panel.padX * 2)
        // Related rows stay tight; the structural gaps come from the Rule
        // separators and the extra space around the hero.
        spacing: Theme.spacingXS
        opacity: panel._entered ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        Column {
            width: parent.width
            spacing: panel.rowGap

            // ── Hero: logo · rank badge · score/account ──────────────────────
            // One unit, not four rows. The rank is a soft badge rather than a
            // bare number so it reads as the card's headline before anything
            // else; points sit beside it at a size that survives a glance.
            Item {
                width: parent.width
                height: Math.max(panel.heroLogoSize, rankBadge.height,
                                 infoCol.implicitHeight)

                FinalsLogo {
                    id: icon
                    size: panel.heroLogoSize
                    errored: logic !== null && logic.errorText !== ""
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    id: rankBadge
                    anchors.left: icon.right
                    anchors.leftMargin: panel.heroGap
                    anchors.verticalCenter: parent.verticalCenter
                    width: rankText.implicitWidth + 14
                    height: rankText.implicitHeight + 4
                    radius: Theme.cornerRadiusS
                    color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.10)
                    border.width: 1
                    border.color: Qt.rgba(panel.accent.r, panel.accent.g,
                                          panel.accent.b, 0.20)

                    StyledText {
                        id: rankText
                        anchors.centerIn: parent
                        text: logic === null ? "" : logic.rankText
                        font.pixelSize: panel.heroNumeric
                            ? panel.rankSize : panel.rankSizeCompact
                        font.weight: Font.Bold
                        font.letterSpacing: -0.6
                        color: panel.accent
                    }
                }

                Column {
                    id: infoCol
                    width: Math.max(0, parent.width - rankBadge.x - rankBadge.width
                                    - panel.heroGap)
                    anchors.left: rankBadge.right
                    anchors.leftMargin: panel.heroGap
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    StyledText {
                        width: parent.width
                        visible: logic !== null && logic.pointsSuffix !== ""
                        text: logic === null || logic.pointsSuffix === ""
                            ? "" : logic.pointsSuffix
                        font.pixelSize: panel.pointsSize
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        // Prefer the name the API resolved over the configured
                        // one — it identifies the account and is what the
                        // season list is keyed on.
                        text: logic === null ? ""
                            : (logic.resolvedName !== "" ? logic.resolvedName : logic.playerName)
                        font.pixelSize: panel.metaSize
                        color: panel.mutedText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }
                }
            }

            // ── Percentile + movement ───────────────────────────────────────
            // Indented to the rank, so it reads as a caption under the figure
            // rather than a full-width row that happens to be nearby. The pill
            // keeps the movement as one object instead of a sentence.
            Row {
                x: panel.rankIndent
                width: Math.max(0, parent.width - panel.rankIndent)
                spacing: Theme.spacingS
                visible: logic !== null && (logic.hasPercentile || panel.hasMovement)
                height: Math.max(percentileText.implicitHeight,
                                 movementPill.height)

                StyledText {
                    id: percentileText
                    width: Math.max(0, parent.width - (movementPill.visible
                                    ? movementPill.width + parent.spacing : 0))
                    text: panel.percentileText
                    font.pixelSize: panel.labelSize
                    color: panel.mutedText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    id: movementPill
                    visible: panel.hasMovement && panel.movementMain !== ""
                    width: movementRow.implicitWidth + 14
                    height: 20
                    radius: 10
                    color: Qt.rgba(panel.movementColor.r, panel.movementColor.g,
                                   panel.movementColor.b, 0.13)
                    border.width: 1
                    border.color: Qt.rgba(panel.movementColor.r, panel.movementColor.g,
                                          panel.movementColor.b, 0.24)
                    anchors.verticalCenter: parent.verticalCenter

                    Row {
                        id: movementRow
                        anchors.centerIn: parent
                        spacing: 5

                        StyledText {
                            text: panel.movementMain
                            font.pixelSize: panel.labelSize
                            font.weight: Font.DemiBold
                            color: panel.movementColor
                            wrapMode: Text.NoWrap
                        }

                        StyledText {
                            text: logic === null ? "" : logic.deltaWindowLabel
                            font.pixelSize: panel.microSize
                            color: Qt.rgba(panel.movementColor.r, panel.movementColor.g,
                                           panel.movementColor.b, 0.70)
                            wrapMode: Text.NoWrap
                        }
                    }
                }
            }

            // ── Trend ────────────────────────────────────────────────────────
            // Two sparklines sharing one width: score above, rank below. Rank is
            // plotted inverted by FinalsLogic, so both read "up is good". The
            // label gutter is sized so the plot begins exactly under the rank.
            Column {
                width: parent.width
                spacing: 3
                visible: logic !== null && (logic.canChart || logic.rankCanChart)

                Row {
                    width: parent.width
                    spacing: panel.chartGap
                    visible: logic !== null && logic.canChart

                    StyledText {
                        text: "score"
                        font.pixelSize: panel.microSize
                        font.letterSpacing: 0.4
                        color: panel.faintText
                        width: panel.chartLabelWidth
                        wrapMode: Text.NoWrap
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Sparkline {
                        width: parent.width - panel.chartLabelWidth - parent.spacing
                        height: 34
                        values: logic === null ? [] : logic.pointsSeries
                        tooltipLabels: panel.pointsTooltip
                        lineColor: panel.scoreTrendColor
                    }
                }

                Row {
                    width: parent.width
                    spacing: panel.chartGap
                    visible: logic !== null && logic.rankCanChart

                    StyledText {
                        text: "rank"
                        font.pixelSize: panel.microSize
                        font.letterSpacing: 0.4
                        color: panel.faintText
                        width: panel.chartLabelWidth
                        wrapMode: Text.NoWrap
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Sparkline {
                        width: parent.width - panel.chartLabelWidth - parent.spacing
                        height: 34
                        values: logic === null ? [] : logic.rankSeries
                        tooltipLabels: panel.rankTooltip
                        lineColor: panel.rankTrendColor
                    }
                }
            }

            // With fewer than three recorded changes there is no trend to draw,
            // so say so rather than showing a straight line that reads as a
            // result. Indented to the plot's left edge.
            StyledText {
                x: panel.rankIndent
                width: Math.max(0, parent.width - panel.rankIndent)
                visible: logic !== null && logic.sampleCount > 0 && !logic.canChart
                text: logic === null ? ""
                    : ("trend builds after 3 changes · " + logic.sampleCount + " so far")
                font.pixelSize: panel.microSize
                color: panel.faintText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }

        Rule {}

        // ── Season: name + countdown, progress, deadline ────────────────────
        // The countdown is the one number that keeps moving, so it gets the
        // monospace face (no jitter) and stronger weight than the season label.
        Column {
            width: parent.width
            spacing: 4

            Item {
                width: parent.width
                height: Math.max(seasonDot.height, seasonLabel.implicitHeight,
                                 countdownText.implicitHeight)

                Rectangle {
                    id: seasonDot
                    width: 6
                    height: 6
                    radius: 3
                    color: logic !== null && logic.seasonDone
                        ? Theme.warning : Theme.primary
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    id: seasonLabel
                    text: logic === null ? "" : logic.seasonName
                    font.pixelSize: panel.labelSize
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.1
                    color: Theme.surfaceText
                    anchors.left: seasonDot.right
                    anchors.leftMargin: panel.rowGap
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, countdownText.x - seasonDot.width
                                    - panel.rowGap * 2)
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                StyledText {
                    id: countdownText
                    text: logic === null ? "" : logic.countdownLong
                    isMonospace: true
                    font.pixelSize: panel.bodySize + 1
                    font.weight: Font.DemiBold
                    color: logic !== null && logic.seasonDone
                        ? Theme.warning : Theme.surfaceText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.NoWrap
                }
            }

            Rectangle {
                width: parent.width
                height: 4
                radius: 2
                color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g,
                               Theme.surfaceVariant.b, 0.82)

                Rectangle {
                    width: parent.width * (logic === null ? 0 : logic.seasonProgress)
                    height: parent.height
                    radius: parent.radius
                    color: logic !== null && logic.seasonDone
                        ? Theme.warning : Theme.primary
                }
            }

            Item {
                width: parent.width
                height: Math.max(seasonEnd.implicitHeight, seasonElapsed.implicitHeight)

                StyledText {
                    id: seasonEnd
                    text: panel.seasonEndText
                    font.pixelSize: panel.metaSize
                    color: panel.faintText
                    width: Math.max(0, parent.width - seasonElapsed.width
                                    - Theme.spacingS)
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    id: seasonElapsed
                    text: panel.seasonElapsedText
                    font.pixelSize: panel.metaSize
                    color: panel.faintText
                    wrapMode: Text.NoWrap
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // Best rank on this board. Only shown when it DIFFERS from the headline —
        // when they are the same (which is the case until you lose places) the
        // row just prints the big number twice.
        Row {
            width: parent.width
            visible: panel.bestIsDistinct

            StyledText {
                text: "best on this board"
                font.pixelSize: panel.labelSize
                color: panel.mutedText
                width: parent.width * 0.62
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            StyledText {
                text: logic === null ? "" : ("#" + logic.bestRank)
                font.pixelSize: panel.labelSize
                font.weight: Font.DemiBold
                color: Theme.primary
                width: parent.width * 0.38
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.NoWrap
            }
        }

        // ── Staleness, off-board explanation ─────────────────────────────────
        // The figure's own age is in the footer. These are the two cases where
        // the footer's calm one-liner is not enough.
        StyledText {
            width: parent.width
            visible: logic !== null && logic.isStale
            text: logic === null ? "" : ("⚠ " + logic.staleText)
            font.pixelSize: panel.metaSize
            color: Theme.warning
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }

        StyledText {
            width: parent.width
            visible: logic !== null && logic.offBoardNote !== ""
            text: logic === null ? "" : logic.offBoardNote
            font.pixelSize: panel.metaSize
            color: panel.mutedText
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }

        // ── Past seasons ─────────────────────────────────────────────────────
        // From /v1/player/{name}. These are season-final figures and do not
        // move, which is why a lagging snapshot is acceptable here — but not
        // for the current board. The header carries the career best and feed
        // age so the list itself stays a clean two-column scan.
        Rule { visible: panel.shownSeasons.length > 0 }

        Column {
            width: parent.width
            spacing: 2
            visible: panel.shownSeasons.length > 0

            Item {
                width: parent.width
                height: Math.max(seasonsHeading.implicitHeight,
                                 seasonsMeta.implicitHeight)

                StyledText {
                    id: seasonsHeading
                    text: "PAST SEASONS"
                    font.pixelSize: panel.microSize
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.1
                    color: panel.faintText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    id: seasonsMeta
                    text: panel.seasonsMetaText
                    font.pixelSize: panel.microSize
                    color: panel.faintText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - seasonsHeading.width
                                    - Theme.spacingS)
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
            }

            Repeater {
                model: panel.shownSeasons

                Row {
                    required property var modelData
                    width: parent.width
                    height: 18

                    StyledText {
                        text: "S" + modelData.season + " "
                            + (logic !== null ? logic.modeLabel(modelData.mode) : modelData.mode)
                        font.pixelSize: panel.labelSize
                        color: panel.mutedText
                        width: parent.width * 0.62
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: modelData.rank > 0 ? ("#" + modelData.rank) : "—"
                        font.pixelSize: panel.labelSize
                        font.weight: Font.DemiBold
                        // Tint the row that is the career best rather than
                        // repeating it as a third column.
                        color: logic !== null && modelData.mode === "quickcash"
                            && modelData.rank === logic.careerBest
                            ? Theme.primary : Theme.surfaceText
                        width: parent.width * 0.38
                        horizontalAlignment: Text.AlignRight
                        wrapMode: Text.NoWrap
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        Rule {}

        // ── Footer ───────────────────────────────────────────────────────────
        // One quiet row: state dot, freshness/rate, refresh control. Everything
        // here is deliberately smaller and dimmer than the hero.
        Row {
            width: parent.width
            spacing: panel.rowGap

            Rectangle {
                width: 6
                height: 6
                radius: 3
                color: panel.liveColor
                opacity: logic !== null && logic.loading ? 0.45 : 1
                anchors.verticalCenter: parent.verticalCenter
                Behavior on opacity {
                    NumberAnimation { duration: 180 }
                }
            }

            StyledText {
                text: panel.statusText
                font.pixelSize: panel.metaSize
                color: logic !== null && (logic.errorText !== "" || logic.isStale)
                    ? Theme.warning : panel.faintText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                width: Math.max(0, parent.width - 6 - refreshBox.width
                                - parent.spacing * 2)
                anchors.verticalCenter: parent.verticalCenter
            }

            // Icon button rather than a text pill: "refresh" was the longest
            // word in the footer and forced the status text to be elided.
            Rectangle {
                id: refreshBox
                width: 26
                height: 26
                radius: Theme.cornerRadiusS
                color: refreshMa.pressed ? Theme.buttonPressed
                    : (refreshMa.containsMouse ? Theme.buttonHover : Theme.buttonBg)
                border.width: 1
                border.color: refreshMa.containsMouse
                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                    : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                DankIcon {
                    id: refreshIcon
                    // sync while a request is in flight, refresh when idle.
                    name: logic !== null && logic.loading ? "sync" : "refresh"
                    size: 15
                    color: refreshMa.enabled ? Theme.buttonText : Theme.surfaceVariantText
                    anchors.centerIn: parent

                    RotationAnimator on rotation {
                        running: logic !== null && logic.loading
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) refreshIcon.rotation = 0
                    }
                }

                MouseArea {
                    id: refreshMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: logic === null || !logic.loading
                    onClicked: panel.refreshRequested()
                }
            }
        }
    }
}

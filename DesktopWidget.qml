import QtQuick
import Quickshell
import QtCore
import qs.Common
import qs.Widgets
import "./Logic"

// DesktopWidget.qml — floating desktop surface for the same data the DankBar
// pill shows. Hosted by DesktopPluginWrapper, which assigns pluginId /
// pluginService / instanceData / widgetWidth / widgetHeight and handles
// right-button drag and resize.
//
// Everything below refers to `fd` and its own properties by bare name: in this
// host a root-qualified lookup does not resolve.
//
// Data and layout come from Logic/, shared with Widget.qml, so this card and the
// bar popout always show identical figures.

Item {
    id: root

    // Assigned by DesktopPluginWrapper
    property string pluginId: ""
    property var    pluginService: null
    property string instanceId: ""
    property var    instanceData: null
    property var    screen: null
    property real   widgetWidth: 280
    property real   widgetHeight: 176
    property var    requestResize: null
    property var    clearResize: null

    // Read by the wrapper before sizing
    readonly property real minWidth: 240
    // Five Quick Cash rows rather than the popout's three. The taller graph,
    // hero and rules push the panel to ~384px at 5 seasons, so the card needs
    // ~24px of chrome slack above that. minHeight must clear the panel or the
    // card clips its own content; defaultHeight adds a little breathing room.
    readonly property real minHeight: 408
    readonly property real defaultWidth: 320
    readonly property real defaultHeight: 420

    // The wrapper assigns pluginService/pluginId from outside, so bindings that
    // read them directly can never be invalidated. Snapshot the settings instead
    // and rebind on snap, so a changed player name or board actually takes
    // effect.
    property var snap: ({})

    function reload() {
        if (!pluginService || !pluginId) {
            snap = ({});
            return;
        }
        var out = {};
        var keys = ["playerName", "board", "platform", "seasonName",
                    "seasonStartIso", "seasonEndIso", "refreshMinutes",
                    "showPoints", "historyEnabled", "retentionDays",
                    "dedupeChanges", "deltaHours",
                    "showPercentile", "showSeasons", "includeSponsors"];
        for (var i = 0; i < keys.length; i++)
            out[keys[i]] = pluginService.loadPluginData(pluginId, keys[i], undefined);
        snap = out;
    }

    onPluginServiceChanged: reload()
    onPluginIdChanged: reload()
    Component.onCompleted: reload()

    // Same construction as Widget.qml — see the note there.
    readonly property string historyPath:
        StandardPaths.writableLocation(StandardPaths.GenericStateLocation)
        + "/DankMaterialShell/plugins/finalsRank/history.jsonl"

    Connections {
        target: pluginService
        enabled: pluginService !== null
        function onPluginDataChanged(changedId) {
            if (changedId === pluginId) reload()
        }
    }

    FinalsLogic {
        id: fd

        playerName:    (snap.playerName || "").trim()
        board:          (snap.board || "s12quickcash").trim()
        platform:       (snap.platform || "crossplay").trim()
        seasonName:     snap.seasonName || "PRIME TIME"
        seasonStartIso: (snap.seasonStartIso || "2026-10-20T13:00:00Z").trim()
        seasonEndIso:   (snap.seasonEndIso || "2027-01-21T13:00:00Z").trim()
        showPoints:     snap.showPoints !== false

        historyEnabled: snap.historyEnabled !== false
        showPercentile: snap.showPercentile !== false
        showSeasons:    snap.showSeasons !== false
        includeSponsors: snap.includeSponsors === true
        retentionDays: {
            var n = parseInt(snap.retentionDays)
            if (isNaN(n) || n < 0) return 120
            return Math.min(730, n)
        }
        dedupeChanges: snap.dedupeChanges !== false
        deltaHours: {
            var n = parseInt(snap.deltaHours)
            return isNaN(n) ? 24 : Math.max(1, Math.min(720, n))
        }
        historyPath: root.historyPath

        refreshMinutes: {
            var n = parseInt(snap.refreshMinutes)
            return isNaN(n) ? 15 : Math.max(5, Math.min(180, n))
        }
    }

    // The soft lift the desktop card needs to read as a floating panel rather
    // than a flat rectangle painted on the wallpaper. Declared before the card
    // and panel so it stays behind them.
    ElevationShadow {
        anchors.fill: parent
        anchors.margins: 4
        level: Theme.elevationLevel2
        targetRadius: Theme.cornerRadiusL
        targetColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.94)
        shadowEnabled: Theme.elevationEnabled
    }

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: 4
        radius: Theme.cornerRadiusL
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.55)

        // Declared before the panel so it sits underneath it: the panel's own
        // refresh button has to stay clickable, and everything else falls
        // straight through an Item that accepts no mouse events.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: fd.loading ? Qt.BusyCursor : Qt.PointingHandCursor
            onClicked: fd.refresh()
        }

        // Top-anchored and content-driven, the same sizing the popout relies on.
        // Anchoring left/right sets the width; the height comes from the panel's
        // own implicitHeight, so the card can never disagree with what it is
        // trying to draw.
        FinalsPanel {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingM
            height: implicitHeight
            desktopChrome: true
            logic: fd
            onRefreshRequested: logic.refresh()
        }
    }
}
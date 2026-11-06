import QtQuick
import qs.Common
import qs.Widgets

// FinalsLogo.qml — the THE FINALS mark, vendored at assets/finals-logo.png.
//
// Mirrors the shared logo component used by the other DMS cards: same component
// shape, same `size` semantics, same fallback behaviour. Sizing is by *height*,
// and `implicitWidth` derives from the artwork's aspect — 26 here to match the
// panel default used elsewhere.
//
// The artwork is 64x64 and square, so unlike the Hive chevrons the aspect is 1
// and both dimensions are equal. Sizing by height is kept anyway so that if a
// non-square asset is dropped in later, the same `size` still means the same
// thing.
//
// The artwork carries THE FINALS brand red in its own fill, so it is
// deliberately not tinted to the theme: recolouring a logo makes it a different
// logo. The error state dims it rather than replacing it — a failed fetch is a
// fact about the data, not about which game it is.
//
// Falls back to the same trophy glyph the bar pill uses if the file is missing
// or fails to decode, so a partially-synced plugin still shows something rather
// than a hole.

Item {
    id: logo

    // Height in px. The bar pills pass a smaller value than the panel: the mark
    // is denser than a Material glyph and turns to mush below about 16px.
    property real size: 26

    property bool errored: false

    // 64x64 from the source PNG, so the aspect is 1.
    readonly property real aspect: 1

    implicitWidth: Math.round(logo.size * logo.aspect)
    implicitHeight: Math.round(logo.size)

    // Only on a hard failure. Testing for "not ready" instead would flash the
    // fallback for a frame on every start, while the async load is in flight.
    readonly property bool missing: img.status === Image.Error

    Image {
        id: img
        anchors.fill: parent
        // Qt.resolvedUrl so the path is anchored to this file rather than the
        // process working directory.
        source: Qt.resolvedUrl("../assets/finals-logo.png")
        // Rasterise at the on-screen size rather than the intrinsic one, so the
        // curves stay clean instead of being scaled down from 64x64.
        sourceSize.width: Math.round(logo.size * logo.aspect) * Math.max(1, Screen.devicePixelRatio)
        sourceSize.height: Math.round(logo.size) * Math.max(1, Screen.devicePixelRatio)
        fillMode: Image.PreserveAspectFit
        smooth: true
        cache: true
        asynchronous: true
        opacity: logo.errored ? 0.4 : 1
        Behavior on opacity {
            NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing }
        }
    }

    // Shown only if the asset is missing or undecodable.
    DankIcon {
        anchors.fill: parent
        name: "emoji_events"
        size: logo.size
        color: logo.errored ? Theme.warning : Theme.primary
        visible: logo.missing
    }
}
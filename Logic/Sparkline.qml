import QtQuick
import qs.Common
import qs.Widgets

// Sparkline.qml — compact trend line for a short numeric series.
//
// A line with a soft gradient fill and a few faint horizontal guides. Normalised
// to its own min/max so the shape is legible however flat or steep the range
// was. No axes or labels — the numbers live in the rows around it and in the
// hover tooltip.
//
// The chart is deliberately not a time series: callers pass change events in
// recorded order. The tooltip is therefore the only way to read an individual
// value, and it follows the nearest recorded point rather than an interpolated
// x position.
//
// Requires at least 3 values. Two points draw a straight line that conveys no
// trend at all, so `hasData` is false below that and the caller shows a
// placeholder instead.

Canvas {
    id: spk

    property var   values: []
    property var   tooltipLabels: []
    property color lineColor: Theme.primary
    property real  lineWidth: 1.75
    property bool  showGrid: true
    property bool  interactive: true

    // Horizontal breathing room so the first/last point markers and the line
    // cap are not clipped by the canvas edge.
    readonly property real plotPad: 2

    // Cursor x in canvas coordinates while hovered; -1 when the pointer is out.
    property real hoverX: -1

    readonly property bool hasData:
        values !== null && values !== undefined && values.length >= 3

    readonly property bool flat: {
        if (!hasData) return false
        var lo = Infinity, hi = -Infinity
        for (var i = 0; i < values.length; i++) {
            if (values[i] < lo) lo = values[i]
            if (values[i] > hi) hi = values[i]
        }
        return hi - lo <= 0
    }

    // The fill is the line colour bleeding downwards, so both stay in step when
    // the caller tints the chart by direction.
    readonly property color fillTop:
        Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.22)
    readonly property color fillBottom:
        Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.0)

    // Immediate rather than Threaded: the hover crosshair repaints on every
    // pointer move, and a threaded canvas adds a visible frame of lag.
    renderStrategy: Canvas.Immediate

    onValuesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onLineWidthChanged: requestPaint()
    onShowGridChanged: requestPaint()
    onTooltipLabelsChanged: requestPaint()
    onHoverXChanged: requestPaint()

    // Nearest recorded point to the pointer. The series has no time axis, so
    // the nearest point is the only honest thing to highlight.
    function _hoverIndex() {
        if (!spk.hasData || spk.hoverX < 0) return -1
        var n = spk.values.length
        var local = Math.max(0, Math.min(spk.width, spk.hoverX) - spk.plotPad)
        var usable = Math.max(1, spk.width - spk.plotPad * 2)
        var i = Math.round(local / usable * (n - 1))
        return Math.max(0, Math.min(n - 1, i))
    }

    function _roundRect(ctx, x, y, w, h, r) {
        ctx.beginPath()
        ctx.moveTo(x + r, y)
        ctx.arcTo(x + w, y, x + w, y + h, r)
        ctx.arcTo(x + w, y + h, x, y + h, r)
        ctx.arcTo(x, y + h, x, y, r)
        ctx.arcTo(x, y, x + w, y, r)
        ctx.closePath()
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()

        if (!spk.hasData) return

        var v = spk.values
        var lo = Infinity
        var hi = -Infinity
        for (var i = 0; i < v.length; i++) {
            if (v[i] < lo) lo = v[i]
            if (v[i] > hi) hi = v[i]
        }
        if (!isFinite(lo) || !isFinite(hi)) return
        // A dead-flat series sits mid-height instead of being pinned to the top
        // by a nominal zero range. Widening by 1 on either side is visually
        // negligible for both points and ranks.
        if (hi - lo <= 0) {
            var mid = lo
            lo = mid - 1
            hi = mid + 1
        }

        var pad = 2
        var h = spk.height
        var w = spk.width
        var n = v.length
        var span = h - pad * 2

        var pts = []
        for (var k = 0; k < n; k++) {
            pts.push({
                x: spk.plotPad + k / (n - 1) * (w - spk.plotPad * 2),
                y: pad + (hi - v[k]) / (hi - lo) * span
            })
        }

        // Faint guides make the vertical movement readable without implying a
        // numeric axis. Drawn under the fill so they never fight the line.
        if (spk.showGrid) {
            ctx.strokeStyle = Qt.rgba(spk.lineColor.r, spk.lineColor.g,
                                      spk.lineColor.b, 0.11).toString()
            ctx.lineWidth = 0.75
            for (var g = 1; g <= 3; g++) {
                var gy = Math.round(h * g / 4) + 0.5
                ctx.beginPath()
                ctx.moveTo(0, gy)
                ctx.lineTo(w, gy)
                ctx.stroke()
            }
        }

        // Fill under the line.
        var grad = ctx.createLinearGradient(0, 0, 0, h)
        grad.addColorStop(0, spk.fillTop.toString())
        grad.addColorStop(1, spk.fillBottom.toString())

        ctx.beginPath()
        ctx.moveTo(pts[0].x, h)
        for (var a = 0; a < pts.length; a++) ctx.lineTo(pts[a].x, pts[a].y)
        ctx.lineTo(pts[pts.length - 1].x, h)
        ctx.closePath()
        ctx.fillStyle = grad
        ctx.fill()

        // A wider, very transparent stroke underneath gives the hairline a
        // subtle glow without a real shadow pass.
        ctx.beginPath()
        for (var b = 0; b < pts.length; b++) {
            if (b === 0) ctx.moveTo(pts[b].x, pts[b].y)
            else ctx.lineTo(pts[b].x, pts[b].y)
        }
        ctx.strokeStyle = Qt.rgba(spk.lineColor.r, spk.lineColor.g,
                                  spk.lineColor.b, 0.16).toString()
        ctx.lineWidth = spk.lineWidth + 3
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.stroke()

        // The line itself.
        ctx.beginPath()
        for (var c = 0; c < pts.length; c++) {
            if (c === 0) ctx.moveTo(pts[c].x, pts[c].y)
            else ctx.lineTo(pts[c].x, pts[c].y)
        }
        ctx.strokeStyle = spk.lineColor.toString()
        ctx.lineWidth = spk.lineWidth
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.stroke()

        // Mark the most recent point so "now" is unambiguous on a chart with no
        // axes. A flat series sits mid-height, which is where it belongs.
        var last = pts[pts.length - 1]
        ctx.beginPath()
        ctx.arc(last.x, last.y, 2, 0, Math.PI * 2)
        ctx.fillStyle = spk.lineColor.toString()
        ctx.fill()

        // Hover: crosshair, a larger point, and a value tooltip. The pointer is
        // snapped to the closest recorded sample, never interpolated.
        var idx = spk._hoverIndex()
        if (idx >= 0) {
            var p = pts[idx]
            ctx.strokeStyle = Qt.rgba(spk.lineColor.r, spk.lineColor.g,
                                      spk.lineColor.b, 0.30).toString()
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(p.x + 0.5, 0)
            ctx.lineTo(p.x + 0.5, h)
            ctx.stroke()

            ctx.beginPath()
            ctx.arc(p.x, p.y, 3, 0, Math.PI * 2)
            ctx.fillStyle = spk.lineColor.toString()
            ctx.fill()
            ctx.strokeStyle = Qt.rgba(0.06, 0.06, 0.07, 0.9).toString()
            ctx.lineWidth = 1
            ctx.stroke()

            var label = idx < spk.tooltipLabels.length ? spk.tooltipLabels[idx] : ""
            if (label !== "") {
                ctx.font = "600 10px sans-serif"
                ctx.textAlign = "left"
                ctx.textBaseline = "middle"
                var tw = ctx.measureText(label).width + 12
                var th = 17
                var tx = p.x + 7
                if (tx + tw > w - 2) tx = p.x - tw - 7
                tx = Math.max(2, Math.min(w - tw - 2, tx))
                var ty = p.y - th - 4
                if (ty < 2) ty = p.y + 5
                ty = Math.max(2, Math.min(h - th - 2, ty))

                spk._roundRect(ctx, tx, ty, tw, th, 5)
                ctx.fillStyle = Qt.rgba(0.055, 0.055, 0.065, 0.95).toString()
                ctx.fill()
                ctx.strokeStyle = Qt.rgba(spk.lineColor.r, spk.lineColor.g,
                                          spk.lineColor.b, 0.38).toString()
                ctx.lineWidth = 1
                ctx.stroke()

                ctx.fillStyle = "#f2f2f4"
                ctx.fillText(label, tx + 6, ty + th / 2 + 0.5)
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        // Hover only: clicks fall through to the host's refresh surface.
        acceptedButtons: Qt.NoButton
        enabled: spk.interactive
        onPositionChanged: function(mouse) { spk.hoverX = mouse.x }
        onExited: spk.hoverX = -1
    }
}

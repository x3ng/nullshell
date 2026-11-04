pragma ComponentBehavior: Bound

import QtQuick
import ".."

Item {
    id: hint
    required property Theme style
    property real progress: 0
    property bool rightCorner: false
    readonly property color accent: style.accent

    implicitWidth: 96
    implicitHeight: 96

    onProgressChanged: canvas.requestPaint()
    onRightCornerChanged: canvas.requestPaint()
    onAccentChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            ctx.save();
            if (hint.rightCorner) {
                ctx.translate(width, 0);
                ctx.scale(-1, 1);
            }

            // Dwell spreads colour across the corner rather than tracing a ring.
            const amount = Math.max(0, Math.min(1, hint.progress));
            const radius = Math.min(width, height) * (0.5 + 0.5 * amount);
            const strength = 0.22 + 0.28 * amount;
            const tint = hint.accent;
            const rgba = alpha => "rgba(" + Math.round(tint.r * 255) + ","
                + Math.round(tint.g * 255) + "," + Math.round(tint.b * 255) + "," + alpha + ")";
            const glow = ctx.createRadialGradient(0, 0, 0, 0, 0, radius);
            glow.addColorStop(0, rgba(strength));
            glow.addColorStop(0.35, rgba(strength * 0.7));
            glow.addColorStop(0.7, rgba(strength * 0.22));
            glow.addColorStop(1, rgba(0));
            ctx.fillStyle = glow;
            ctx.fillRect(0, 0, width, height);

            ctx.restore();
        }
    }
}

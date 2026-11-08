import QtQuick

// Match the 1.5px rounded strokes used by StatusIcon.
Canvas {
    id: glyph
    required property color ink
    required property color surface
    property real level: 1
    property bool charging: false
    implicitWidth: 24
    implicitHeight: 20
    onInkChanged: requestPaint()
    onSurfaceChanged: requestPaint()
    onLevelChanged: requestPaint()
    onChargingChanged: requestPaint()
    onPaint: {
        const c = getContext("2d");
        c.reset();
        c.strokeStyle = ink;
        c.fillStyle = ink;
        c.lineWidth = 1.5;
        c.lineCap = "round";
        c.lineJoin = "round";
        c.beginPath();
        c.moveTo(4, 5); c.lineTo(17, 5);
        c.quadraticCurveTo(19, 5, 19, 7); c.lineTo(19, 13);
        c.quadraticCurveTo(19, 15, 17, 15); c.lineTo(4, 15);
        c.quadraticCurveTo(2, 15, 2, 13); c.lineTo(2, 7);
        c.quadraticCurveTo(2, 5, 4, 5); c.closePath(); c.stroke();
        c.beginPath(); c.moveTo(22, 8.5); c.lineTo(22, 11.5); c.stroke();
        c.globalAlpha = 0.85;
        c.fillRect(4.5, 7.5, Math.max(0, Math.min(1, level)) * 12, 5);
        c.globalAlpha = 1;
        if (charging) {
            c.beginPath();
            c.moveTo(12, 3); c.lineTo(7, 11); c.lineTo(11, 11);
            c.lineTo(9, 17); c.lineTo(15, 8); c.lineTo(11, 8); c.closePath();
            c.lineWidth = 2.5;
            c.strokeStyle = surface; c.stroke();
            c.fill();
        }
    }
}

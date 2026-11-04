pragma ComponentBehavior: Bound

import QtQuick

// Small line icons drawn in the current palette, independent of icon fonts.
Canvas {
    id: icon
    required property string kind
    required property color ink
    property bool muted: false
    property real level: 1
    property real strokeWidth: 1.5
    implicitWidth: 20
    implicitHeight: 20
    onKindChanged: requestPaint()
    onInkChanged: requestPaint()
    onMutedChanged: requestPaint()
    onLevelChanged: requestPaint()
    onStrokeWidthChanged: requestPaint()
    // Draw in a 20×20 design grid, then scale to the actual item size.
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const c = getContext("2d");
        c.reset();
        if (width !== 20 || height !== 20) c.scale(width / 20, height / 20);
        c.strokeStyle = ink;
        c.fillStyle = ink;
        c.lineWidth = icon.strokeWidth;
        c.lineCap = "round";
        c.lineJoin = "round";
        if (kind === "battery") {
            c.strokeRect(2, 5, 14, 10);
            c.fillRect(17, 8, 2, 4);
            c.fillRect(4, 7, Math.max(0, Math.min(1, level)) * 10, 6);
        } else if (kind === "volume") {
            c.beginPath();
            c.moveTo(2, 8); c.lineTo(5, 8); c.lineTo(9, 4);
            c.lineTo(9, 16); c.lineTo(5, 12); c.lineTo(2, 12); c.closePath(); c.stroke();
            c.beginPath();
            if (muted) {
                c.moveTo(13, 7); c.lineTo(18, 13);
                c.moveTo(18, 7); c.lineTo(13, 13);
            } else {
                c.arc(8, 10, 6, -0.7, 0.7);
                c.moveTo(8 + Math.cos(-0.7) * 10, 10 + Math.sin(-0.7) * 10);
                c.arc(8, 10, 10, -0.7, 0.7);
            }
            c.stroke();
        } else if (kind === "settings") {
            c.beginPath();
            for (let i = 0; i < 32; i++) {
                const angle = i * Math.PI / 16;
                const radius = i % 4 < 2 ? 8 : 6;
                const x = 10 + Math.cos(angle) * radius;
                const y = 10 + Math.sin(angle) * radius;
                if (i === 0) c.moveTo(x, y); else c.lineTo(x, y);
            }
            c.closePath(); c.stroke();
            c.beginPath(); c.arc(10, 10, 2.5, 0, Math.PI * 2); c.stroke();
        } else if (kind === "bell") {
            c.beginPath(); c.moveTo(3, 14); c.lineTo(5, 11); c.lineTo(5, 8);
            c.arc(10, 8, 5, Math.PI, 0); c.lineTo(15, 11); c.lineTo(17, 14);
            c.closePath(); c.stroke();
            c.beginPath(); c.arc(10, 16, 2, 0, Math.PI); c.stroke();
        } else if (kind === "lock") {
            c.beginPath();
            c.moveTo(6, 9); c.lineTo(14, 9);
            c.quadraticCurveTo(16, 9, 16, 11); c.lineTo(16, 15);
            c.quadraticCurveTo(16, 17, 14, 17); c.lineTo(6, 17);
            c.quadraticCurveTo(4, 17, 4, 15); c.lineTo(4, 11);
            c.quadraticCurveTo(4, 9, 6, 9); c.closePath(); c.stroke();
            c.beginPath(); c.moveTo(6.5, 9); c.lineTo(6.5, 6.5);
            c.arc(10, 6.5, 3.5, Math.PI, 0); c.lineTo(13.5, 9); c.stroke();
            c.beginPath(); c.moveTo(10, 12); c.lineTo(10, 14); c.stroke();
        } else if (kind === "search") {
            c.beginPath(); c.arc(8.5, 8.5, 5.5, 0, Math.PI * 2); c.stroke();
            c.beginPath(); c.moveTo(12.5, 12.5); c.lineTo(17.5, 17.5); c.stroke();
        } else if (kind === "keyboard") {
            c.strokeRect(1.5, 4, 17, 12);
            for (let row = 0; row < 2; row++) {
                for (let column = 0; column < 5; column++)
                    c.fillRect(4 + column * 2.5, 7 + row * 3, 1.2, 1.2);
            }
            c.beginPath(); c.moveTo(6, 14); c.lineTo(14, 14); c.stroke();
        } else if (kind === "brightness") {
            c.beginPath(); c.arc(10, 10, 3.5, 0, Math.PI * 2); c.stroke();
            for (let i = 0; i < 8; i++) {
                const angle = i * Math.PI / 4;
                c.beginPath();
                c.moveTo(10 + Math.cos(angle) * 6, 10 + Math.sin(angle) * 6);
                c.lineTo(10 + Math.cos(angle) * 8.5, 10 + Math.sin(angle) * 8.5);
                c.stroke();
            }
        } else if (kind === "appearance") {
            c.beginPath(); c.arc(10, 10, 7, 0, Math.PI * 2); c.stroke();
            c.beginPath();
            c.arc(10, 10, 7, level > 0 ? -Math.PI / 2 : Math.PI / 2,
                level > 0 ? Math.PI / 2 : Math.PI * 1.5);
            c.closePath(); c.fill();
        } else if (kind === "wifi") {
            for (let radius of [4, 7, 10]) {
                c.beginPath(); c.arc(10, 16, radius, -Math.PI * 0.77, -Math.PI * 0.23); c.stroke();
            }
            c.beginPath(); c.arc(10, 16, 1, 0, Math.PI * 2); c.fill();
        } else if (kind === "bluetooth") {
            c.beginPath(); c.moveTo(10, 2); c.lineTo(15, 6); c.lineTo(5, 14);
            c.moveTo(5, 6); c.lineTo(15, 14); c.lineTo(10, 18); c.lineTo(10, 2); c.stroke();
        } else if (kind === "power") {
            c.beginPath(); c.arc(10, 11, 7, -Math.PI * 0.3, Math.PI * 1.3); c.stroke();
            c.beginPath(); c.moveTo(10, 2); c.lineTo(10, 10); c.stroke();
        } else if (kind === "music") {
            c.beginPath(); c.arc(6, 15, 3, 0, Math.PI * 2); c.fill();
            c.beginPath(); c.arc(14, 13, 3, 0, Math.PI * 2); c.fill();
            c.beginPath();
            c.moveTo(9, 15); c.lineTo(9, 5); c.lineTo(17, 3); c.lineTo(17, 13);
            c.stroke();
        } else if (kind === "play") {
            c.beginPath(); c.moveTo(6, 4.5); c.lineTo(16, 10); c.lineTo(6, 15.5);
            c.closePath(); c.stroke();
        } else if (kind === "pause") {
            c.beginPath();
            c.moveTo(7, 5); c.lineTo(7, 15);
            c.moveTo(13, 5); c.lineTo(13, 15);
            c.stroke();
        } else if (kind === "prev") {
            c.beginPath();
            c.moveTo(5, 5); c.lineTo(5, 15);
            c.moveTo(16, 5); c.lineTo(7, 10); c.lineTo(16, 15);
            c.stroke();
        } else if (kind === "next") {
            c.beginPath();
            c.moveTo(4, 5); c.lineTo(13, 10); c.lineTo(4, 15);
            c.moveTo(15, 5); c.lineTo(15, 15);
            c.stroke();
        } else if (kind === "chevron") {
            c.beginPath(); c.moveTo(7.5, 5); c.lineTo(13, 10); c.lineTo(7.5, 15);
            c.stroke();
        } else if (kind === "back") {
            c.beginPath(); c.moveTo(12.5, 5); c.lineTo(7, 10); c.lineTo(12.5, 15);
            c.stroke();
        } else if (kind === "check") {
            c.beginPath(); c.moveTo(4, 11); c.lineTo(8.5, 15.5); c.lineTo(16, 6);
            c.stroke();
        } else if (kind === "minus") {
            c.beginPath(); c.moveTo(4, 10); c.lineTo(16, 10); c.stroke();
        } else if (kind === "trash") {
            c.beginPath(); c.moveTo(4, 5); c.lineTo(16, 5);
            c.moveTo(8, 5); c.lineTo(8, 3); c.lineTo(12, 3); c.lineTo(12, 5);
            c.moveTo(5, 5); c.lineTo(6, 17); c.lineTo(14, 17); c.lineTo(15, 5);
            c.moveTo(8, 8); c.lineTo(8.5, 14);
            c.moveTo(12, 8); c.lineTo(11.5, 14); c.stroke();
        } else if (kind === "close") {
            c.beginPath();
            c.moveTo(5, 5); c.lineTo(15, 15);
            c.moveTo(15, 5); c.lineTo(5, 15);
            c.stroke();
        } else if (kind === "window") {
            c.strokeRect(3, 4, 14, 12);
            c.beginPath(); c.moveTo(3, 8); c.lineTo(17, 8); c.stroke();
        } else if (kind === "app") {
            c.beginPath();
            c.moveTo(10, 3); c.lineTo(17, 10); c.lineTo(10, 17); c.lineTo(3, 10);
            c.closePath(); c.stroke();
        } else if (kind === "moon") {
            // Crescent: the outer circle's arc closed by the bite
            // circle's inner arc, so the outline is one closed shape.
            c.beginPath();
            c.arc(10, 10, 7, 0.424, 4.288);
            c.arc(13.5, 6.5, 7, 3.566, 1.147, true);
            c.closePath();
            c.stroke();
        } else if (kind === "mic") {
            // Capsule mic in a holder arc with a stem base.
            c.beginPath();
            c.arc(10, 6, 2, Math.PI, 0);
            c.moveTo(8, 6); c.lineTo(8, 10);
            c.moveTo(12, 6); c.lineTo(12, 10);
            c.arc(10, 10, 2, 0, Math.PI);
            c.stroke();
            c.beginPath();
            c.arc(10, 10, 5, Math.PI * 0.12, Math.PI * 0.88);
            c.moveTo(10, 15); c.lineTo(10, 17);
            c.moveTo(7, 17); c.lineTo(13, 17);
            c.stroke();
        } else if (kind === "headphones") {
            c.beginPath(); c.arc(10, 11, 7, Math.PI, Math.PI * 2); c.stroke();
            c.fillRect(2.5, 11, 3, 6);
            c.fillRect(14.5, 11, 3, 6);
        } else if (kind === "coffee") {
            c.beginPath();
            c.moveTo(3, 7); c.lineTo(14, 7); c.lineTo(14, 12);
            c.quadraticCurveTo(14, 15, 11, 15); c.lineTo(6, 15);
            c.quadraticCurveTo(3, 15, 3, 12); c.closePath(); c.stroke();
            c.beginPath(); c.moveTo(14, 8); c.lineTo(16, 8);
            c.arc(16, 10, 2, -Math.PI / 2, Math.PI / 2);
            c.lineTo(14, 12); c.stroke();
            c.beginPath(); c.moveTo(3, 18); c.lineTo(15, 18);
            c.moveTo(6, 2); c.lineTo(6, 4);
            c.moveTo(10, 2); c.lineTo(10, 4); c.stroke();
        } else if (kind === "eye") {
            c.beginPath();
            c.moveTo(3, 10);
            c.quadraticCurveTo(10, 3, 17, 10);
            c.quadraticCurveTo(10, 17, 3, 10);
            c.closePath();
            c.stroke();
            c.beginPath(); c.arc(10, 10, 2.5, 0, Math.PI * 2); c.fill();
        } else if (kind === "leaf") {
            c.beginPath();
            c.moveTo(10, 17);
            c.quadraticCurveTo(3, 10, 10, 3);
            c.quadraticCurveTo(17, 10, 10, 17);
            c.closePath();
            c.stroke();
            c.beginPath(); c.moveTo(10, 16); c.lineTo(10, 6); c.stroke();
        } else if (kind === "balance") {
            // Seesaw: beam, fulcrum, pivot stem.
            c.beginPath();
            c.moveTo(4, 8); c.lineTo(16, 8);
            c.moveTo(10, 6); c.lineTo(10, 13);
            c.stroke();
            c.beginPath();
            c.moveTo(7, 17); c.lineTo(10, 12); c.lineTo(13, 17);
            c.closePath(); c.stroke();
        } else if (kind === "gauge") {
            // Speedometer: dial arc, needle up-right, pivot.
            c.beginPath(); c.arc(10, 11, 7, Math.PI * 0.9, Math.PI * 2.1); c.stroke();
            c.beginPath();
            c.moveTo(10, 11); c.lineTo(12.6, 6.8);
            c.stroke();
            c.beginPath(); c.arc(10, 11, 1.5, 0, Math.PI * 2); c.fill();
        } else if (kind === "calendar") {
            c.strokeRect(3, 4, 14, 13);
            c.beginPath(); c.moveTo(3, 8); c.lineTo(17, 8);
            c.moveTo(7, 2); c.lineTo(7, 5); c.moveTo(13, 2); c.lineTo(13, 5); c.stroke();
            c.fillRect(6, 11, 2, 2); c.fillRect(11, 11, 2, 2);
        }
    }
}

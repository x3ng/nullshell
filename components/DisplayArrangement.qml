pragma ComponentBehavior: Bound

import QtQuick

Rectangle {
    id: canvas
    required property var style
    required property var outputs
    required property int selected
    signal outputSelected(int index)
    signal outputMoved(int index, int x, int y)

    radius: style.radiusControl
    color: style.backgroundSurface
    border.color: style.separator
    border.width: 1
    clip: true

    function layoutWidth(output) { return (output.transform % 2 ? output.height : output.width) / Math.max(0.25, output.scale); }
    function layoutHeight(output) { return (output.transform % 2 ? output.width : output.height) / Math.max(0.25, output.scale); }
    function boundedPosition(value) { return Math.max(-65536, Math.min(65536, Math.round(value))); }

    readonly property var screens: outputs.filter(o => o.enabled && !o.mirror_of && o.width > 0 && o.height > 0)
    readonly property real leftEdge: screens.length ? Math.min(...screens.map(o => o.x)) : 0
    readonly property real topEdge: screens.length ? Math.min(...screens.map(o => o.y)) : 0
    readonly property real spanX: screens.length ? Math.max(1, Math.max(...screens.map(o => o.x + layoutWidth(o))) - leftEdge) : 1
    readonly property real spanY: screens.length ? Math.max(1, Math.max(...screens.map(o => o.y + layoutHeight(o))) - topEdge) : 1
    readonly property real factor: Math.max(0.0001, Math.min((width - 24) / spanX, (height - 24) / spanY))

    Repeater {
        model: canvas.outputs
        Rectangle {
            id: tile
            required property var modelData
            required property int index
            objectName: "arrangement-output-" + modelData.name
            property real dragX: 0
            property real dragY: 0
            visible: modelData.enabled && !modelData.mirror_of
            x: (canvas.width - canvas.spanX * canvas.factor) / 2 + (modelData.x - canvas.leftEdge) * canvas.factor + dragX
            y: (canvas.height - canvas.spanY * canvas.factor) / 2 + (modelData.y - canvas.topEdge) * canvas.factor + dragY
            width: Math.max(8, canvas.layoutWidth(modelData) * canvas.factor)
            height: Math.max(8, canvas.layoutHeight(modelData) * canvas.factor)
            radius: canvas.style.radiusCard
            color: canvas.selected === index ? canvas.style.surfaceSelected : canvas.style.surfaceRaised
            border.color: canvas.selected === index ? canvas.style.accent : canvas.style.outline
            z: canvas.selected === index ? 1 : 0
            border.width: 1

            Text {
                anchors.fill: parent
                anchors.margins: 3
                text: tile.modelData.name
                color: canvas.style.textPrimary
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                font.family: canvas.style.fontFamily
                font.pixelSize: canvas.style.fontSizeSmall
                font.weight: canvas.selected === tile.index ? Font.DemiBold : Font.Normal
            }
            MouseArea {
                anchors.fill: parent
                // The outer page may scroll, but a gesture started on a tile
                // belongs to the arrangement until release or cancellation.
                preventStealing: true
                property point origin
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: mouse => {
                    origin = mapToItem(canvas, mouse.x, mouse.y);
                    canvas.outputSelected(tile.index);
                }
                onPositionChanged: mouse => {
                    if (!pressed) return;
                    const point = mapToItem(canvas, mouse.x, mouse.y);
                    tile.dragX = point.x - origin.x;
                    tile.dragY = point.y - origin.y;
                }
                onCanceled: { tile.dragX = 0; tile.dragY = 0; }
                onReleased: mouse => {
                    const point = mapToItem(canvas, mouse.x, mouse.y);
                    const dx = point.x - origin.x;
                    const dy = point.y - origin.y;
                    tile.dragX = 0;
                    tile.dragY = 0;
                    if (Math.abs(dx) + Math.abs(dy) < 3) return;
                    canvas.outputMoved(tile.index,
                        canvas.boundedPosition(tile.modelData.x + dx / canvas.factor),
                        canvas.boundedPosition(tile.modelData.y + dy / canvas.factor));
                }
            }
        }
    }
}

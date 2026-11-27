pragma ComponentBehavior: Bound

import QtQuick
import "DisplayGeometry.js" as Geometry

Rectangle {
    id: canvas
    required property var style
    required property var outputs
    required property int selected
    // Outputs reported by DisplayGeometry.issues(); highlighted, not moved.
    property var problemNames: []
    signal outputSelected(int index)
    signal outputMoved(int index, int x, int y)

    radius: style.radiusControl
    color: style.backgroundSurface
    border.color: style.separator
    border.width: 1
    clip: true

    // Magnet distances are measured on screen so they feel the same at any zoom.
    readonly property real enterDistance: 10 / factor
    readonly property real exitDistance: 16 / factor
    readonly property var rects: Geometry.rects(outputs)
    readonly property real leftEdge: rects.length ? Math.min(...rects.map(item => item.x0)) : 0
    readonly property real topEdge: rects.length ? Math.min(...rects.map(item => item.y0)) : 0
    readonly property real spanX: rects.length ? Math.max(1, Math.max(...rects.map(item => item.x1)) - leftEdge) : 1
    readonly property real spanY: rects.length ? Math.max(1, Math.max(...rects.map(item => item.y1)) - topEdge) : 1
    readonly property real factor: Math.max(0.0001, Math.min((width - 24) / spanX, (height - 24) / spanY))

    property int dragIndex: -1
    property var dragResult: null
    property point dragOrigin
    property real dragStartX: 0
    property real dragStartY: 0
    property bool dragMoved: false
    readonly property bool dragging: dragIndex >= 0

    function layoutWidth(output) { return Geometry.logicalSize(output).width; }
    function layoutHeight(output) { return Geometry.logicalSize(output).height; }
    function boundedPosition(value) { return Math.max(-65536, Math.min(65536, Math.round(value))); }
    function canvasX(world) { return (canvas.width - canvas.spanX * canvas.factor) / 2 + (world - canvas.leftEdge) * canvas.factor; }
    function canvasY(world) { return (canvas.height - canvas.spanY * canvas.factor) / 2 + (world - canvas.topEdge) * canvas.factor; }
    function worldX(point) { return (point - (canvas.width - canvas.spanX * canvas.factor) / 2) / canvas.factor + canvas.leftEdge; }
    function worldY(point) { return (point - (canvas.height - canvas.spanY * canvas.factor) / 2) / canvas.factor + canvas.topEdge; }

    // One solver for dragging, typed coordinates and the keyboard.
    function settle(index, rawX, rawY, held) {
        const output = outputs[index];
        if (!output) return {x:Math.round(rawX), y:Math.round(rawY), guideX:null, guideY:null, snapped:false};
        const size = Geometry.logicalSize(output);
        const others = Geometry.rects(outputs).filter(item => item.name !== output.name);
        return Geometry.snap(rawX, rawY, size.width, size.height, others,
            {enter: canvas.enterDistance, exit: canvas.exitDistance, held: held});
    }
    function beginDrag(index, point) {
        const output = outputs[index];
        if (!output) return;
        canvas.dragIndex = index;
        canvas.dragOrigin = point;
        canvas.dragStartX = output.x;
        canvas.dragStartY = output.y;
        canvas.dragMoved = false;
        canvas.dragResult = {x:output.x, y:output.y, guideX:null, guideY:null, snapped:false};
        canvas.outputSelected(index);
    }
    function updateDrag(point) {
        if (!canvas.dragging) return;
        const rawX = canvas.dragStartX + (point.x - canvas.dragOrigin.x) / canvas.factor;
        const rawY = canvas.dragStartY + (point.y - canvas.dragOrigin.y) / canvas.factor;
        if (Math.abs(point.x - canvas.dragOrigin.x) + Math.abs(point.y - canvas.dragOrigin.y) >= 2)
            canvas.dragMoved = true;
        const held = canvas.dragResult.snapped ? canvas.dragResult : null;
        canvas.dragResult = canvas.settle(canvas.dragIndex, rawX, rawY, held);
    }
    function endDrag(point) {
        if (!canvas.dragging) return;
        canvas.updateDrag(point);
        const index = canvas.dragIndex;
        const result = canvas.dragResult;
        const moved = canvas.dragMoved;
        canvas.cancelDrag();
        if (moved) canvas.outputMoved(index, canvas.boundedPosition(result.x), canvas.boundedPosition(result.y));
    }
    function cancelDrag() {
        canvas.dragIndex = -1;
        canvas.dragResult = null;
        canvas.dragMoved = false;
    }
    // Records a placement that did not come from this canvas (tests, keyboard).
    function commitDrag(index, rawX, rawY) {
        const result = canvas.settle(index, rawX, rawY, null);
        canvas.outputMoved(index, canvas.boundedPosition(result.x), canvas.boundedPosition(result.y));
        return result;
    }
    // Runs a pointer gesture through the same handlers as the MouseArea: press on
    // the tile centre, move to a layout position, then release unless previewing.
    function dragTo(index, rawX, rawY, release) {
        const output = outputs[index];
        if (!output) return false;
        const size = Geometry.logicalSize(output);
        canvas.beginDrag(index, Qt.point(canvas.canvasX(output.x + size.width / 2),
            canvas.canvasY(output.y + size.height / 2)));
        const point = Qt.point(canvas.canvasX(rawX + size.width / 2), canvas.canvasY(rawY + size.height / 2));
        canvas.updateDrag(point);
        if (release !== false) canvas.endDrag(point);
        return true;
    }
    function nudge(index, dx, dy) {
        const output = outputs[index];
        if (!output || output.mirror_of) return;
        canvas.outputMoved(index, canvas.boundedPosition(output.x + dx), canvas.boundedPosition(output.y + dy));
    }
    function hasProblem(name) { return canvas.problemNames.indexOf(name) >= 0; }

    Rectangle {
        visible: canvas.dragging && canvas.dragResult && canvas.dragResult.guideX !== null
        x: canvas.dragResult ? canvas.canvasX(canvas.dragResult.guideX) : 0
        y: 0
        width: 1
        height: canvas.height
        color: canvas.style.accent
        opacity: 0.8
    }
    Rectangle {
        visible: canvas.dragging && canvas.dragResult && canvas.dragResult.guideY !== null
        x: 0
        y: canvas.dragResult ? canvas.canvasY(canvas.dragResult.guideY) : 0
        width: canvas.width
        height: 1
        color: canvas.style.accent
        opacity: 0.8
    }

    Repeater {
        model: canvas.outputs
        Rectangle {
            id: tile
            required property var modelData
            required property int index
            objectName: "arrangement-output-" + modelData.name
            readonly property bool moving: canvas.dragging && canvas.dragIndex === index
            readonly property bool placed: modelData.enabled && !modelData.mirror_of
            visible: placed
            x: canvas.canvasX(moving && canvas.dragResult ? canvas.dragResult.x : modelData.x)
            y: canvas.canvasY(moving && canvas.dragResult ? canvas.dragResult.y : modelData.y)
            width: Math.max(8, canvas.layoutWidth(modelData) * canvas.factor)
            height: Math.max(8, canvas.layoutHeight(modelData) * canvas.factor)
            radius: canvas.style.radiusCard
            color: canvas.selected === index ? canvas.style.surfaceSelected : canvas.style.surfaceRaised
            border.color: canvas.hasProblem(modelData.name) ? canvas.style.danger
                : canvas.selected === index ? canvas.style.accent : canvas.style.outline
            z: moving || canvas.selected === index ? 1 : 0
            border.width: 1
            opacity: moving ? 0.9 : 1
            activeFocusOnTab: visible
            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData.name + " at " + modelData.x + ", " + modelData.y
            Accessible.checked: canvas.selected === index
            Accessible.onPressAction: canvas.outputSelected(index)
            Keys.onLeftPressed: canvas.nudge(index, event.modifiers & Qt.ShiftModifier ? -1 : -8, 0)
            Keys.onRightPressed: canvas.nudge(index, event.modifiers & Qt.ShiftModifier ? 1 : 8, 0)
            Keys.onUpPressed: canvas.nudge(index, 0, event.modifiers & Qt.ShiftModifier ? -1 : -8)
            Keys.onDownPressed: canvas.nudge(index, 0, event.modifiers & Qt.ShiftModifier ? 1 : 8)
            Keys.onEscapePressed: event => {
                event.accepted = canvas.dragging;
                canvas.cancelDrag();
            }
            onActiveFocusChanged: if (activeFocus) canvas.outputSelected(index)

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
                    tile.forceActiveFocus();
                    origin = mapToItem(canvas, mouse.x, mouse.y);
                    canvas.beginDrag(tile.index, origin);
                }
                onPositionChanged: mouse => {
                    if (pressed) canvas.updateDrag(mapToItem(canvas, mouse.x, mouse.y));
                }
                onCanceled: canvas.cancelDrag();
                onReleased: mouse => canvas.endDrag(mapToItem(canvas, mouse.x, mouse.y));
            }
        }
    }
}

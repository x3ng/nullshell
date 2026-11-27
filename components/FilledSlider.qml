pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import ".."

ClippingRectangle {
    id: slider
    required property Theme style
    required property real value
    required property string label
    property bool available: true
    signal edited(real newValue)

    activeFocusOnTab: available
    Accessible.role: Accessible.Slider
    Accessible.name: label + ", " + percentage.text
    function step(direction) { if (available) edited(Math.max(0, Math.min(1, value + direction * 0.02))); }
    Keys.onLeftPressed: step(-1)
    Keys.onRightPressed: step(1)
    Accessible.onIncreaseAction: step(1)
    Accessible.onDecreaseAction: step(-1)

    // Neutral fill keeps the label readable and matches other filled controls.
    implicitWidth: 240
    implicitHeight: 36
    radius: style.radiusControl
    color: style.surfaceRaised
    opacity: available ? 1 : 0.5

    Rectangle {
        width: slider.width * Math.max(0, Math.min(1, slider.value))
        height: slider.height
        radius: 0
        color: slider.style.meterFill
    }
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: percentage.left
        anchors.rightMargin: slider.style.spaceSm
        elide: Text.ElideRight
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: slider.label
        color: slider.style.textPrimary
        font.family: slider.style.fontFamily
        font.pixelSize: slider.style.fontSizeSmall
        font.weight: Font.Medium
    }
    Text {
        id: percentage
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: slider.available ? Math.round(slider.value * 100) + "%" : "Unavailable"
        color: slider.style.textPrimary
        font.family: slider.style.fontFamily
        font.pixelSize: slider.style.fontSizeSmall
    }
    Rectangle {
        anchors.fill: parent
        visible: slider.activeFocus
        color: "transparent"
        radius: slider.radius
        border.width: slider.style.focusWidth
        border.color: slider.style.focusInk
    }
    MouseArea {
        anchors.fill: parent
        enabled: slider.available
        function update(x) { slider.edited(Math.max(0, Math.min(1, x / width))); }
        onPressed: mouse => update(mouse.x)
        onPositionChanged: mouse => { if (pressed) update(mouse.x); }
        onWheel: event => {
            slider.edited(Math.max(0, Math.min(1, slider.value + (event.angleDelta.y > 0 ? 0.02 : -0.02))));
            event.accepted = true;
        }
    }
}

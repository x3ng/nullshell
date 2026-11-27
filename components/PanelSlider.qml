import QtQuick
import QtQuick.Controls
import ".."

Slider {
    id: adjustment
    required property Theme style
    property bool muted: false
    property bool showHandle: false
    background: Rectangle {
        x: adjustment.leftPadding
        y: adjustment.topPadding + adjustment.availableHeight / 2 - height / 2
        width: adjustment.availableWidth
        height: 6
        radius: 3
        color: adjustment.style.sliderTrack
        Rectangle {
            width: adjustment.visualPosition * parent.width
            height: parent.height
            radius: 3
            color: adjustment.muted ? adjustment.style.textMuted : adjustment.style.accent
            opacity: adjustment.enabled ? 1 : 0.4
        }
    }
    handle: Rectangle {
        x: adjustment.leftPadding + adjustment.visualPosition * (adjustment.availableWidth - width)
        y: adjustment.topPadding + adjustment.availableHeight / 2 - height / 2
        width: 12; height: 12; radius: 6
        color: adjustment.style.accent
        border.width: adjustment.activeFocus ? 2 : 0
        border.color: adjustment.style.focusInk
        visible: adjustment.showHandle || adjustment.hovered || adjustment.pressed || adjustment.activeFocus
    }
}

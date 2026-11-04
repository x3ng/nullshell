pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."

Item {
    id: level
    required property Theme style
    required property var actions
    required property string title
    required property string icon
    required property real value
    property bool available: true
    property bool muted: false
    property string action: ""
    property string detailsAction: ""
    signal edited(real value)
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.minimumWidth: 0
    implicitHeight: 44
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: level.width < 220 ? 4 : 8
    Item {
        Layout.preferredWidth: 28
        Layout.preferredHeight: 32
        ChoiceButton {
            anchors.fill: parent
            visible: level.action !== ""
            style: level.style
            label: ""
            StatusIcon {
                anchors.centerIn: parent
                width: 20; height: 20
                kind: level.icon
                muted: level.muted
                ink: level.muted ? level.style.textMuted : level.style.textSecondary
            }
            tooltip: level.muted ? "Unmute output" : "Mute output"
            available: level.available
            onTriggered: level.actions.execute(level.action)
        }
        StatusIcon {
            anchors.centerIn: parent
            width: 20; height: 20
            visible: level.action === ""
            kind: level.icon
            ink: level.style.textSecondary
        }
    }
    Slider {
        id: adjustment
        Layout.fillWidth: true
        implicitHeight: 36
        Layout.minimumWidth: 48
        from: 0; to: 1; stepSize: 0.02
        value: level.value
        enabled: level.available
        activeFocusOnTab: true
        Accessible.name: level.title
        onMoved: level.edited(value)
        background: Rectangle {
            x: adjustment.leftPadding
            y: adjustment.topPadding + adjustment.availableHeight / 2 - height / 2
            width: adjustment.availableWidth
            height: 6
            radius: 3
            color: level.style.separator
            Rectangle {
                width: adjustment.visualPosition * parent.width
                height: parent.height
                radius: 3
                color: level.muted ? level.style.textMuted : level.style.accent
                opacity: level.available ? 1 : 0.4
            }
        }
        handle: Rectangle {
            x: adjustment.leftPadding + adjustment.visualPosition * (adjustment.availableWidth - width)
            y: adjustment.topPadding + adjustment.availableHeight / 2 - height / 2
            width: 12; height: 12; radius: 6
            color: level.style.accent
            visible: adjustment.hovered || adjustment.pressed || adjustment.activeFocus
        }
    }
    Text {
        Layout.preferredWidth: 42
        horizontalAlignment: Text.AlignRight
        text: level.available ? Math.round(level.value * 100) + "%" : "—"
        color: level.muted ? level.style.textMuted : level.style.textSecondary
        font.family: level.style.fontFamily
        font.pixelSize: 14
    }
    ChoiceButton {
        visible: level.detailsAction !== ""
        Layout.preferredWidth: 28
        Layout.preferredHeight: 32
        style: level.style
        label: ""
        iconKind: "headphones"
        iconSize: 20
        tooltip: "Audio devices and microphone"
        onTriggered: level.actions.execute(level.detailsAction)
    }

    }
}

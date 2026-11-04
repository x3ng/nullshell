pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."

Rectangle {
    id: tile
    required property Theme style
    required property string icon
    required property string title
    required property string detail
    property bool available: true
    property bool toggleable: false
    property bool toggleAvailable: true
    property bool active: false
    signal triggered()
    signal toggled()
    implicitHeight: 72
    implicitWidth: 240
    radius: style.radiusCard
    color: mouse.containsMouse ? style.surfaceHover : style.surfaceRaised
    border.width: 0
    border.color: style.separator
    opacity: available ? 1 : 0.5
    Behavior on color { ColorAnimation { duration: 140 } }
    RowLayout {
        anchors.fill: parent
        anchors.margins: tile.style.spaceMd
        spacing: tile.style.spaceMd
        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            radius: 12
            color: tile.active ? tile.style.accent : tile.style.surfaceHover
            StatusIcon {
                anchors.centerIn: parent
                width: 20; height: 20
                kind: tile.icon
                ink: tile.active ? tile.style.accentInk : tile.style.textSecondary
            }
            MouseArea {
                id: toggleMouse
                anchors.fill: parent
                enabled: tile.toggleable && tile.available && tile.toggleAvailable
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: tile.toggled()
            }
            ShellToolTip {
                style: tile.style
                visible: toggleMouse.containsMouse
                text: tile.active ? "Turn off " + tile.title : "Turn on " + tile.title
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: tile.style.spaceXs
            Text {
                Layout.fillWidth: true
                text: tile.title
                color: tile.style.textPrimary
                font.family: tile.style.fontFamily
                font.pixelSize: tile.style.fontSizeBody
                font.weight: Font.Medium
            }
            Text {
                Layout.fillWidth: true
                text: tile.available ? tile.detail : "Unavailable"
                elide: Text.ElideRight
                color: tile.style.textMuted
                font.family: tile.style.fontFamily
                font.pixelSize: tile.style.fontSizeSmall
            }
        }
        StatusIcon {
            kind: "chevron"
            width: 18
            height: 18
            ink: tile.style.textMuted
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.leftMargin: tile.toggleable ? 60 : 0
        enabled: tile.available
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.triggered()
    }
}

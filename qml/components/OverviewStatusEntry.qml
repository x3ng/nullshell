pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."

Rectangle {
    id: entry
    required property Theme style
    required property var actions
    required property string icon
    required property string title
    required property string detail
    property string secondary: ""
    required property string action
    property bool online: false
    property bool available: true
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    implicitHeight: 44
    radius: entry.style.radiusControl
    color: entryMouse.containsMouse ? entry.style.surfaceHover : "transparent"
    border.width: activeFocus ? 1 : 0
    border.color: entry.style.accent
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: title + ": " + detail + (secondary ? ", " + secondary : "")
    Accessible.onPressAction: entry.actions.execute(entry.action)
    Keys.onReturnPressed: entry.actions.execute(entry.action)
    Keys.onEnterPressed: entry.actions.execute(entry.action)
    Keys.onSpacePressed: entry.actions.execute(entry.action)
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10
        StatusIcon {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            kind: entry.icon
            ink: entry.online ? entry.style.accent : entry.style.textMuted
        }
        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: entry.detail
            textFormat: Text.PlainText
            font.family: entry.style.fontFamily
            font.pixelSize: 16
            font.weight: Font.Medium
            color: entry.available ? entry.style.textPrimary : entry.style.textMuted
            elide: Text.ElideRight
            maximumLineCount: 1
        }
        Text {
            Layout.maximumWidth: entry.width * 0.42
            visible: entry.secondary !== ""
            text: entry.secondary
            textFormat: Text.PlainText
            font.family: entry.style.fontFamily
            font.pixelSize: 14
            color: entry.style.textSecondary
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
    ShellToolTip {
        style: entry.style
        visible: entryMouse.containsMouse || entry.activeFocus
        text: entry.title + " · " + entry.detail + (entry.secondary ? " · " + entry.secondary : "")
    }
    MouseArea {
        id: entryMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: entry.actions.execute(entry.action)
    }

}

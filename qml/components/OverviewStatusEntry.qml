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
    Accessible.name: title + ": " + detail
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
            color: entry.available ? entry.style.textPrimary : entry.style.textMuted
            elide: Text.ElideRight
            maximumLineCount: 1
        }
        Text {
            text: "›"
            color: entry.style.textMuted
            font.pixelSize: 20
            opacity: entryMouse.containsMouse || entry.activeFocus ? 1 : 0.45
        }
    }
    ShellToolTip {
        style: entry.style
        visible: entryMouse.containsMouse || entry.activeFocus
        text: entry.title + " · " + entry.detail
    }
    MouseArea {
        id: entryMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: entry.actions.execute(entry.action)
    }

}

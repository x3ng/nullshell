pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: row
    required property Theme style
    required property string title
    property string subtitle: ""
    property bool selected: false
    property bool available: true
    property bool expanded: false
    property string iconKind: ""
    signal triggered()
    activeFocusOnTab: visible && available
    Accessible.role: Accessible.Button
    Accessible.name: title + (subtitle ? ", " + subtitle : "")
    Accessible.onPressAction: { if (available) triggered(); }
    Keys.onReturnPressed: { if (available) triggered(); }
    Keys.onSpacePressed: { if (available) triggered(); }
    implicitHeight: subtitle ? 54 : 44
    radius: style.radiusControl
    color: selected ? style.surfaceSelected : mouse.containsMouse ? style.surfaceHover : "transparent"
    opacity: available ? 1 : 0.5
    border.width: expanded || activeFocus ? 1 : 0
    border.color: style.accent
    Behavior on color { ColorAnimation { duration: 120 } }
    RowLayout {
        anchors.fill: parent
        anchors.margins: row.style.spaceMd
        spacing: 10
        StatusIcon {
            visible: row.iconKind !== ""
            kind: row.iconKind
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            ink: row.selected ? row.style.accent : row.style.textMuted
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: row.style.spaceXs
            Text {
                Layout.fillWidth: true
                text: row.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: row.selected ? row.style.textSelected : row.style.textPrimary
                font.family: row.style.fontFamily
                font.pixelSize: row.style.fontSizeBody
                font.weight: row.selected ? Font.Medium : Font.Normal
            }
            Text {
                Layout.fillWidth: true
                visible: row.subtitle !== ""
                text: row.subtitle
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: row.style.textMuted
                font.family: row.style.fontFamily
                font.pixelSize: row.style.fontSizeCaption
            }
        }
        StatusIcon {
            kind: row.selected ? "check" : "chevron"
            width: 16
            height: 16
            ink: row.selected ? row.style.accent : row.style.textMuted
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: row.available
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.triggered()
    }
}

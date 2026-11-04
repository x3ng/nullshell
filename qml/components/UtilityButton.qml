pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: button
    required property Theme style
    required property string label
    required property string iconKind
    property string tooltip: ""
    property bool selected: false
    property bool checkable: false
    property bool available: true
    property int iconSize: 20
    signal triggered()
    implicitHeight: 36
    radius: 8
    color: selected ? style.surfaceSelected
        : pointer.containsMouse && available ? style.surfaceHover : "transparent"
    border.width: activeFocus ? 1 : 0
    border.color: style.accent
    opacity: available ? 1 : 0.4
    activeFocusOnTab: visible && available
    Accessible.role: checkable ? Accessible.CheckBox : Accessible.Button
    Accessible.checkable: checkable
    Accessible.checked: selected
    Accessible.name: label || tooltip
    Accessible.onPressAction: { if (available) triggered(); }
    Keys.onReturnPressed: { if (available) triggered(); }
    Keys.onEnterPressed: { if (available) triggered(); }
    Keys.onSpacePressed: { if (available) triggered(); }
    Behavior on color { ColorAnimation { duration: 100 } }
    RowLayout {
        anchors.centerIn: parent
        width: Math.min(implicitWidth, button.width - 16)
        spacing: 8
        StatusIcon {
            Layout.preferredWidth: button.iconSize
            Layout.preferredHeight: button.iconSize
            kind: button.iconKind
            strokeWidth: 2
            ink: button.selected ? button.style.accent : button.style.textSecondary
        }
        Text {
            visible: button.label !== ""
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: button.label
            elide: Text.ElideRight
            color: button.selected ? button.style.accent : button.style.textSecondary
            font.family: button.style.fontFamily
            font.pixelSize: 14
            font.weight: Font.Normal
        }

    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: button.available
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.triggered()
    }
    ShellToolTip {
        style: button.style
        visible: pointer.containsMouse && button.tooltip !== ""
        text: button.tooltip
    }
}

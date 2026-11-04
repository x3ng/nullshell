import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: header
    required property Theme style
    required property string title
    property string subtitle: ""
    property alias actions: actionRow.data
    signal backRequested()
    implicitHeight: 32
    Layout.fillWidth: true
    Layout.preferredHeight: 32
    Layout.minimumHeight: 32
    spacing: 8
    ChoiceButton {
        Layout.preferredWidth: 30
        Layout.preferredHeight: 30
        style: header.style
        label: ""
        iconKind: "back"
        tooltip: "Back to overview"
        iconSize: 16
        onTriggered: header.backRequested()
    }
    Text {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        elide: Text.ElideRight
        text: header.title
        color: header.style.textPrimary
        font.family: header.style.fontFamily
        font.pixelSize: 15
        font.weight: Font.Medium
        HoverHandler { id: titleHover }
        ShellToolTip { style: header.style; visible: titleHover.hovered && header.subtitle !== ""; text: header.subtitle }
    }
    RowLayout { id: actionRow; spacing: 6 }
}

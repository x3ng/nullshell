import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: header
    required property Theme style
    required property string title
    property string subtitle: ""
    property string backTooltip: "Back to overview"
    property string backIcon: "back"
    property alias actions: actionRow.data
    signal backRequested()
    Layout.fillWidth: true
    Layout.preferredHeight: style.controlHeight
    Layout.minimumHeight: style.controlHeight
    spacing: style.spaceSm
    ChoiceButton {
        compact: true
        style: header.style
        label: ""
        iconKind: header.backIcon
        tooltip: header.backTooltip
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
        font.pixelSize: header.style.fontSizeBody
        font.weight: Font.DemiBold
        HoverHandler { id: titleHover }
        ShellToolTip { style: header.style; visible: titleHover.hovered && header.subtitle !== ""; text: header.subtitle }
    }
    RowLayout { id: actionRow; spacing: header.style.spaceXs }
}

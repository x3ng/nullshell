import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: header
    required property Theme style
    required property string title
    property string subtitle: ""
    property bool showSubtitle: false
    property string backTooltip: "Back to overview"
    property string backIcon: "back"
    property alias actions: actionRow.data
    signal backRequested()
    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(style.controlHeight, heading.implicitHeight)
    Layout.minimumHeight: Layout.preferredHeight
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
    ColumnLayout {
        id: heading
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 2
        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: header.title
            color: header.style.textPrimary
            font.family: header.style.fontFamily
            font.pixelSize: header.style.fontSizeTitle
            font.weight: Font.DemiBold
        }
        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            visible: header.showSubtitle && text !== ""
            elide: Text.ElideRight
            text: header.subtitle
            color: header.style.textSecondary
            font.family: header.style.fontFamily
            font.pixelSize: header.style.fontSizeLabel
        }
        HoverHandler { id: titleHover }
        ShellToolTip { style: header.style; visible: titleHover.hovered && header.subtitle !== ""; text: header.subtitle }
    }
    RowLayout { id: actionRow; spacing: header.style.spaceXs }
}

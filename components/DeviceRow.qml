pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: row
    required property Theme style
    required property string title
    property string subtitle: ""
    property bool selectionOnly: false
    property bool selected: false
    property bool available: true
    property bool expanded: false
    property string iconKind: ""
    property bool showChevron: true
    // Horizontal insets let rows inside a card align icons and chevrons with sibling controls.
    property int leftInset: style.spaceMd
    property int rightInset: style.spaceMd
    // Leading icon slot; wider slots put the label on a shared rail with sibling rows.
    property int iconSlot: 20
    property int titleWeight: Font.Normal
    signal triggered()
    activeFocusOnTab: visible && available
    Accessible.role: selectionOnly ? Accessible.RadioButton : Accessible.Button
    Accessible.checkable: selectionOnly
    Accessible.checked: selectionOnly && selected
    Accessible.name: title + (subtitle ? ", " + subtitle : "")
    Accessible.onPressAction: { if (available) triggered(); }
    Keys.onReturnPressed: { if (available) triggered(); }
    Keys.onEnterPressed: { if (available) triggered(); }
    Keys.onSpacePressed: { if (available) triggered(); }
    implicitHeight: subtitle ? 60 : 44
    radius: style.radiusControl
    readonly property bool hovered: mouse.containsMouse && available
    color: selectionOnly && selected ? (hovered ? style.surfaceSelectedHover : style.surfaceSelected)
        : hovered ? style.surfaceHover
        : selectionOnly || expanded ? style.cardSurface : "transparent"
    opacity: available ? 1 : 0.55
    border.width: activeFocus ? style.focusWidth : 0
    border.color: style.focusInk
    RowLayout {
        anchors.fill: parent
        anchors.topMargin: row.style.spaceMd
        anchors.bottomMargin: row.style.spaceMd
        anchors.leftMargin: row.leftInset
        anchors.rightMargin: row.rightInset
        spacing: row.style.spaceMd
        Item {
            visible: row.iconKind !== ""
            Layout.preferredWidth: row.iconSlot
            Layout.preferredHeight: 20
            StatusIcon {
                anchors.centerIn: parent
                width: 20; height: 20
                kind: row.iconKind
                ink: row.selected ? row.style.accent : row.style.textSecondary
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: row.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: row.selected ? row.style.textSelected : row.style.textPrimary
                font.family: row.style.fontFamily
                font.pixelSize: row.style.fontSizeBody
                font.weight: row.selected ? Font.Medium : row.titleWeight
            }
            Text {
                Layout.fillWidth: true
                visible: row.subtitle !== ""
                text: row.subtitle
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: row.style.textMuted
                font.family: row.style.fontFamily
                font.pixelSize: row.style.fontSizeLabel
            }
        }
        StatusIcon {
            visible: row.selectionOnly ? row.selected : row.showChevron
            kind: row.selected ? "check" : "chevron"
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
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

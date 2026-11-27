pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: entry
    required property Theme style
    required property var actions
    required property string icon
    required property string title
    required property string detail
    required property string action
    property string secondary: ""
    property string error: ""
    property string toggleAction: ""
    property string toggleTooltip: ""
    property bool online: false
    property bool activeConnection: false
    property bool available: true

    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.minimumWidth: 0
    implicitHeight: 56
    radius: entry.style.radiusCard
    color: rowHover.hovered ? entry.style.surfaceHover : entry.style.cardSurface
    border.width: detailsButton.activeFocus ? entry.style.focusWidth : 0
    border.color: entry.style.focusInk

    HoverHandler { id: rowHover }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 8
        spacing: 10

        UtilityButton {
            id: toggleButton
            objectName: "quick-" + entry.action + "-toggle"
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            style: entry.style
            label: ""
            iconKind: entry.icon
            iconSize: 18
            color: !entry.available ? entry.style.controlSurface
                : entry.activeConnection ? (toggleButton.hovered ? Qt.darker(entry.style.accent, 1.10) : entry.style.accent)
                : entry.online ? (toggleButton.hovered ? entry.style.surfaceSelectedHover : entry.style.surfaceSelected)
                : (toggleButton.hovered ? entry.style.surfaceHover : entry.style.controlSurface)
            iconInk: !entry.available ? entry.style.textDisabled
                : entry.activeConnection ? entry.style.accentInk
                : entry.online ? entry.style.accent : entry.style.textMuted
            checkable: true
            Accessible.checked: entry.online
            available: entry.available && entry.actions.available(entry.toggleAction)
            tooltip: entry.toggleTooltip
            onTriggered: entry.actions.execute(entry.toggleAction)
        }

        ChoiceButton {
            id: detailsButton
            objectName: "quick-" + entry.action + "-details"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.fillHeight: true
            style: entry.style
            color: "transparent"
            border.width: 0
            label: ""
            tooltip: "Open " + entry.title + " settings · " + (entry.error || entry.secondary || entry.detail)
            Accessible.name: entry.title + ", " + entry.detail + (entry.secondary ? ", " + entry.secondary : "")
            onTriggered: entry.actions.execute(entry.action)

            RowLayout {
                anchors.fill: parent
                spacing: 6

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: entry.detail
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: entry.available ? entry.style.textPrimary : entry.style.textDisabled
                        font.family: entry.style.fontFamily
                        font.pixelSize: entry.style.fontSizeSmall
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: entry.error !== "" || entry.secondary !== ""
                        text: entry.error || entry.secondary
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: entry.error ? entry.style.danger
                            : entry.activeConnection ? entry.style.textSecondary : entry.style.textMuted
                        font.family: entry.style.fontFamily
                        font.pixelSize: entry.style.fontSizeCaption
                        font.weight: entry.activeConnection ? Font.Medium : Font.Normal
                    }
                }

                StatusIcon {
                    kind: "chevron"
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    opacity: rowHover.hovered || detailsButton.activeFocus ? 0.9 : 0.45
                    ink: entry.style.textMuted
                }
            }
        }
    }
}

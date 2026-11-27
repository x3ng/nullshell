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
    implicitHeight: 52
    radius: entry.style.radiusCard
    // Whole-tile tonal surface: no nested colored square patch around the icon.
    color: !entry.available ? entry.style.cardSurface
        : entry.activeConnection ? (toggleButton.hovered || detailsButton.hovered ? entry.style.surfaceSelectedHover : entry.style.surfaceSelected)
        : (toggleButton.hovered || detailsButton.hovered ? entry.style.surfaceHover : entry.style.cardSurface)

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Main left region toggles the radio directly; clean icon + two-line label, no inner box.
        UtilityButton {
            id: toggleButton
            objectName: "quick-" + entry.action + "-toggle"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.fillHeight: true
            style: entry.style
            color: "transparent"
            label: ""
            iconKind: ""
            checkable: true
            Accessible.checked: entry.online
            Accessible.name: entry.toggleTooltip + " · " + entry.detail + (entry.secondary ? ", " + entry.secondary : "")
            available: entry.available && entry.actions.available(entry.toggleAction)
            tooltip: entry.toggleTooltip
            onTriggered: entry.actions.execute(entry.toggleAction)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 8
                spacing: 12

                StatusIcon {
                    kind: entry.icon
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    ink: !entry.available ? entry.style.textDisabled
                        : entry.activeConnection || entry.online ? entry.style.accent
                        : entry.style.textMuted
                }

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
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 24
            color: entry.activeConnection ? Qt.alpha(entry.style.textPrimary, 0.12) : entry.style.separator
            opacity: 0.8
        }

        // Trailing segment opens the network / Bluetooth device list.
        ChoiceButton {
            id: detailsButton
            objectName: "quick-" + entry.action + "-details"
            Layout.preferredWidth: 36
            Layout.fillHeight: true
            style: entry.style
            color: detailsButton.hovered ? Qt.alpha(entry.style.textPrimary, 0.06) : "transparent"
            label: ""
            iconKind: "chevron"
            iconSize: 16
            iconInk: detailsButton.hovered ? entry.style.textPrimary : entry.style.textMuted
            tooltip: "Open " + entry.title + " settings"
            Accessible.name: "Open " + entry.title + " settings"
            onTriggered: entry.actions.execute(entry.action)
        }
    }
}

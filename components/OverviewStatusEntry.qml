pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
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
    property bool available: true
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.minimumWidth: 0
    implicitHeight: 44
    spacing: entry.style.spaceSm
    UtilityButton {
        objectName: "quick-" + entry.action + "-toggle"
        Layout.preferredWidth: 40
        Layout.preferredHeight: 32
        style: entry.style
        label: ""
        iconKind: entry.icon
        checkable: true
        // Status text carries the radio state; avoid a selected tile on the home page.
        Accessible.checked: entry.online
        available: entry.available && entry.actions.available(entry.toggleAction)
        tooltip: entry.toggleTooltip
        onTriggered: entry.actions.execute(entry.toggleAction)
    }
    ChoiceButton {
        objectName: "quick-" + entry.action + "-details"
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredHeight: 44
        style: entry.style
        label: ""
        tooltip: "Open " + entry.title + " settings · " + (entry.error || entry.detail)
        Accessible.name: tooltip + ", " + entry.detail
        onTriggered: entry.actions.execute(entry.action)
        RowLayout {
            anchors.fill: parent
            anchors.margins: entry.style.spaceXs
            spacing: entry.style.spaceSm
            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: entry.error || entry.detail
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: entry.error ? entry.style.danger : entry.available ? entry.style.textPrimary : entry.style.textDisabled
                font.family: entry.style.fontFamily
                font.pixelSize: entry.style.fontSizeBody
                // Live status names read one step above the settings directory.
                font.weight: Font.Medium
            }
            Text {
                visible: entry.available && entry.secondary !== "" && entry.error === ""
                Layout.maximumWidth: parent.width * 0.38
                text: entry.secondary
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: entry.style.textMuted
                font.family: entry.style.fontFamily
                font.pixelSize: entry.style.fontSizeLabel
            }
            StatusIcon {
                kind: "chevron"
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                ink: entry.style.textMuted
            }
        }
    }
}

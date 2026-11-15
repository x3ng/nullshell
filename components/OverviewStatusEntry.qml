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
    implicitHeight: 52
    spacing: 4
    UtilityButton {
        objectName: "quick-" + entry.action + "-toggle"
        Layout.preferredWidth: 40
        Layout.preferredHeight: 40
        style: entry.style
        label: ""
        iconKind: entry.icon
        checkable: true
        selected: entry.online
        available: entry.available && entry.actions.available(entry.toggleAction)
        tooltip: entry.toggleTooltip
        onTriggered: entry.actions.execute(entry.toggleAction)
    }
    ChoiceButton {
        objectName: "quick-" + entry.action + "-details"
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredHeight: 48
        style: entry.style
        label: ""
        tooltip: "Open " + entry.title + " settings · " + (entry.error || entry.detail)
        Accessible.name: tooltip + ", " + entry.detail
        onTriggered: entry.actions.execute(entry.action)
        RowLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 6
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: entry.title
                    color: entry.style.textSecondary
                    font.family: entry.style.fontFamily
                    font.pixelSize: 12
                }
                Text {
                    Layout.fillWidth: true
                    text: entry.error || (entry.detail + (entry.secondary ? " · " + entry.secondary : ""))
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: entry.error ? entry.style.danger : entry.available ? entry.style.textPrimary : entry.style.textMuted
                    font.family: entry.style.fontFamily
                    font.pixelSize: 14
                }
            }
            Text {
                text: "›"
                color: entry.style.textSecondary
                font.pixelSize: 22
            }
        }
    }
}

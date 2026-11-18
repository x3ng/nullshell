pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: tools
    required property Theme style
    required property var services
    required property var actions
    spacing: 4
    UtilityButton {
        objectName: "power-menu-button"
        Layout.preferredWidth: 32
        Layout.preferredHeight: 32
        style: tools.style
        label: ""
        iconKind: "power"
        iconSize: 18
        tooltip: "Power and session"
        onTriggered: tools.actions.execute("session")
    }
    UtilityButton {
        id: awakeButton
        Layout.preferredWidth: 32
        Layout.preferredHeight: 32
        style: tools.style
        label: ""
        iconKind: "coffee"
        iconSize: 18
        checkable: true
        selected: tools.services.keepAwake
        tooltip: tools.services.keepAwakeUntil > 0
            ? "Keep awake until " + Qt.formatTime(new Date(tools.services.keepAwakeUntil), "hh:mm") + (tools.services.keepAwakeRequested ? " · Permanent setting also on" : "")
            : tools.services.keepAwake ? "Keep awake: on · Click to resume idle" : "Keep awake: off · Click to prevent idle"
        onTriggered: tools.actions.execute("keep-awake")
    }
}

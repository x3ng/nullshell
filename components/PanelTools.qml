pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: tools
    required property Theme style
    required property var services
    required property var appearance
    required property var actions
    spacing: 4
    UtilityButton {
        id: appearanceButton
        Layout.preferredWidth: 32
        Layout.preferredHeight: 32
        style: tools.style
        label: ""
        iconKind: tools.appearance.darkMode ? "moon" : "brightness"
        iconSize: 18
        available: tools.appearance.appearanceAvailable
        tooltip: tools.appearance.darkMode ? "Switch to light appearance" : "Switch to dark appearance"
        onTriggered: tools.actions.execute(tools.appearance.darkMode ? "light" : "dark")
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
        tooltip: tools.services.keepAwake ? "Keep awake: on · Click to resume idle" : "Keep awake: off · Click to prevent idle"
        onTriggered: tools.actions.execute("keep-awake")
    }
    UtilityButton {
        id: lockButton
        Layout.preferredWidth: 32
        Layout.preferredHeight: 32
        style: tools.style
        label: ""
        iconKind: "lock"
        iconSize: 18
        tooltip: "Lock screen"
        available: tools.actions.available("lock")
        onTriggered: tools.actions.execute("lock")
    }
}

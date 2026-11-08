pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

GridLayout {
    id: controls
    required property Theme style
    required property var actions
    required property var services
    readonly property var system: services.controls
    columns: width >= 480 ? 2 : 1
    columnSpacing: 12
    rowSpacing: 12

    ControlTile {
        Layout.fillWidth: true
        style: controls.style
        icon: "wifi"
        title: "Wi-Fi"
        detail: controls.system.wifiEnabled ? controls.system.wifiConnection : "Off"
        available: controls.system.wifiAvailable
        active: controls.system.wifiEnabled
        toggleable: true
        toggleAvailable: controls.actions.available("wifi-toggle")
        onTriggered: controls.actions.execute("wifi")
        onToggled: controls.actions.execute("wifi-toggle")
    }
    ControlTile {
        Layout.fillWidth: true
        style: controls.style
        icon: "bluetooth"
        title: "Bluetooth"
        detail: !controls.system.bluetoothEnabled ? "Off"
            : controls.system.bluetoothConnected.length
                ? controls.system.bluetoothConnected.length + " connected"
                : "No devices connected"
        available: controls.system.bluetoothAvailable
        active: controls.system.bluetoothEnabled
        toggleable: true
        toggleAvailable: controls.actions.available("bluetooth-toggle")
        onTriggered: controls.actions.execute("bluetooth")
        onToggled: controls.actions.execute("bluetooth-toggle")
    }
}

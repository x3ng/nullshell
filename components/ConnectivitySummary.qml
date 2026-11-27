pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

GridLayout {
    id: summary
    required property Theme style
    required property var actions
    required property var system
    property bool singleColumn: false
    readonly property var network: system.wifiNetworks.find(network => network.connected) ?? null
    readonly property var devices: system.bluetoothDevices.filter(device => device.connected)
    readonly property bool wifiConnected: system.wifiEnabled && !system.wifiBusy && !!system.wifiConnection && system.wifiConnection !== "Not connected"
    readonly property bool btConnected: system.bluetoothEnabled && !system.bluetoothBusy && devices.length > 0
    columns: singleColumn || width < 440 ? 1 : 2
    columnSpacing: 10
    rowSpacing: 8

    OverviewStatusEntry {
        style: summary.style
        actions: summary.actions
        icon: "wifi"
        title: "Wi-Fi"
        error: summary.system.wifiError
        detail: !summary.system.wifiAvailable ? "Wi-Fi"
            : summary.wifiConnected ? summary.system.wifiConnection : "Wi-Fi"
        secondary: !summary.system.wifiAvailable ? "Unavailable"
            : summary.system.wifiBusy ? "Changing state…"
            : !summary.system.wifiEnabled ? "Off"
            : summary.wifiConnected ? (summary.network ? "Connected · " + Math.round(summary.network.signalStrength * 100) + "%" : "Connected")
            : "Not connected"
        online: summary.system.wifiEnabled
        activeConnection: summary.wifiConnected
        toggleAction: "wifi-toggle"
        toggleTooltip: summary.system.wifiBusy ? "Changing Wi-Fi…" : summary.system.wifiEnabled ? "Turn off Wi-Fi" : "Turn on Wi-Fi"
        available: summary.system.wifiAvailable
        action: "wifi"
    }

    OverviewStatusEntry {
        style: summary.style
        actions: summary.actions
        icon: "bluetooth"
        title: "Bluetooth"
        error: summary.system.bluetoothError
        detail: !summary.system.bluetoothAvailable ? "Bluetooth"
            : summary.btConnected ? (summary.devices[0].name || summary.devices[0].address) : "Bluetooth"
        secondary: !summary.system.bluetoothAvailable ? "Unavailable"
            : summary.system.bluetoothBusy ? "Changing state…"
            : !summary.system.bluetoothEnabled ? "Off"
            : summary.btConnected ? [
                "Connected",
                summary.devices[0].batteryAvailable ? Math.round(summary.devices[0].battery * 100) + "%" : "",
                summary.devices.length > 1 ? "+" + (summary.devices.length - 1) : ""
            ].filter(text => text !== "").join(" · ")
            : "Not connected"
        online: summary.system.bluetoothEnabled
        activeConnection: summary.btConnected
        toggleAction: "bluetooth-toggle"
        toggleTooltip: summary.system.bluetoothBusy ? "Changing Bluetooth…" : summary.system.bluetoothEnabled ? "Turn off Bluetooth" : "Turn on Bluetooth"
        available: summary.system.bluetoothAvailable
        action: "bluetooth"
    }
}

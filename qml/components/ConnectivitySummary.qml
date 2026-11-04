pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: summary
    required property Theme style
    required property var actions
    required property var system
    readonly property var network: system.wifiNetworks.find(network => network.connected) ?? null
    readonly property var devices: system.bluetoothDevices.filter(device => device.connected)
    spacing: 16
    OverviewStatusEntry {
        style: summary.style
        actions: summary.actions
        icon: "wifi"
        title: "Wi-Fi"
        secondary: summary.network ? Math.round(summary.network.signalStrength * 100) + "% signal" : ""
        detail: !summary.system.wifiAvailable ? "Unavailable"
            : summary.system.wifiEnabled ? summary.system.wifiConnection || "Not connected" : "Wi-Fi off"
        online: summary.system.wifiEnabled && summary.system.wifiNetworks.some(network => network.connected)
        available: summary.system.wifiAvailable
        action: "wifi"
    }
    OverviewStatusEntry {
        style: summary.style
        actions: summary.actions
        icon: "bluetooth"
        title: "Bluetooth"
        secondary: summary.devices.length ? [
            summary.devices[0].batteryAvailable ? Math.round(summary.devices[0].battery * 100) + "% battery" : "",
            summary.devices.length > 1 ? "+" + (summary.devices.length - 1) : ""
        ].filter(text => text !== "").join(" · ") : ""
        detail: !summary.system.bluetoothAvailable ? "Unavailable"
            : !summary.system.bluetoothEnabled ? "Off"
            : summary.devices.length ? (summary.devices[0].name || summary.devices[0].address) : "Not connected"
        online: summary.system.bluetoothEnabled && summary.system.bluetoothConnected.length > 0
        available: summary.system.bluetoothAvailable
        action: "bluetooth"
    }
}

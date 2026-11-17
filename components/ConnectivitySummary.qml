pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

GridLayout {
    id: summary
    required property Theme style
    required property var actions
    required property var system
    readonly property var network: system.wifiNetworks.find(network => network.connected) ?? null
    readonly property var devices: system.bluetoothDevices.filter(device => device.connected)
    columns: width < 500 ? 1 : 2
    columnSpacing: style.spaceLg
    rowSpacing: style.spaceSm
    OverviewStatusEntry {
        style: summary.style
        actions: summary.actions
        icon: "wifi"
        title: "Wi-Fi"
        error: summary.system.wifiError
        secondary: summary.system.wifiEnabled && !summary.system.wifiBusy && summary.network ? Math.round(summary.network.signalStrength * 100) + "% signal" : ""
        detail: !summary.system.wifiAvailable ? "Unavailable"
            : summary.system.wifiBusy ? "Changing Wi-Fi…"
            : summary.system.wifiEnabled ? summary.system.wifiConnection || "Not connected" : "Wi-Fi off"
        online: summary.system.wifiEnabled
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
        secondary: summary.system.bluetoothEnabled && !summary.system.bluetoothBusy && summary.devices.length ? [
            summary.devices[0].batteryAvailable ? Math.round(summary.devices[0].battery * 100) + "% battery" : "",
            summary.devices.length > 1 ? "+" + (summary.devices.length - 1) : ""
        ].filter(text => text !== "").join(" · ") : ""
        detail: !summary.system.bluetoothAvailable ? "Unavailable"
            : summary.system.bluetoothBusy ? "Changing Bluetooth…"
            : !summary.system.bluetoothEnabled ? "Bluetooth off"
            : summary.devices.length ? (summary.devices[0].name || summary.devices[0].address) : "Not connected"
        online: summary.system.bluetoothEnabled
        toggleAction: "bluetooth-toggle"
        toggleTooltip: summary.system.bluetoothBusy ? "Changing Bluetooth…" : summary.system.bluetoothEnabled ? "Turn off Bluetooth" : "Turn on Bluetooth"
        available: summary.system.bluetoothAvailable
        action: "bluetooth"
    }
}

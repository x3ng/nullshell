import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower

// Read-only login/lock information. No session, authentication or power actions.
Scope {
    id: root
    property bool active: false
    readonly property bool hyprland: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== ""
    readonly property var battery: UPower.displayDevice
    readonly property bool batteryReady: !!battery?.ready && !!battery?.isPresent
        && Number.isFinite(battery.percentage) && battery.percentage >= 0 && battery.percentage <= 1
    readonly property string batteryText: !batteryReady ? "" : "Battery " + Math.round(battery.percentage * 100) + "%"
        + (battery.state === UPowerDeviceState.Charging ? " · Charging"
            : battery.state === UPowerDeviceState.FullyCharged ? " · Fully charged"
            : !UPower.onBattery ? " · Plugged in" : "")
    readonly property bool batteryLow: batteryReady && UPower.onBattery && battery.percentage <= 0.2
    property string keyboardLayout: ""
    property bool capsLock: false

    function clearKeyboard() { keyboardLayout = ""; capsLock = false; }
    function refreshKeyboard() {
        if (active && hyprland) refresh.restart();
    }
    onActiveChanged: {
        clearKeyboard();
        if (active) refreshKeyboard();
        else { refresh.stop(); if (probe.running) probe.kill(); }
    }
    Component.onCompleted: refreshKeyboard()
    Connections {
        target: root.hyprland ? Hyprland : null
        function onRawEvent(event) {
            if (["activelayout", "configreloaded"].includes(event.name)) root.refreshKeyboard();
        }
    }
    Timer {
        id: refresh
        interval: 80
        onTriggered: {
            if (!root.active) return;
            if (probe.running) restart();
            else probe.running = true;
        }
    }
    Process {
        id: probe
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector { id: output }
        onExited: (code, status) => {
            root.clearKeyboard();
            if (!root.active || code !== 0 || status !== 0) return;
            try {
                const keyboards = JSON.parse(output.text).keyboards;
                const main = Array.isArray(keyboards) ? keyboards.filter(k => k.main === true) : [];
                if (main.length !== 1) return;
                root.keyboardLayout = typeof main[0].active_keymap === "string" ? main[0].active_keymap : "";
                root.capsLock = main[0].capsLock === true;
            } catch (_) { /* Unavailable information stays hidden. */ }
        }
    }
    Timer { interval: 2000; running: probe.running; onTriggered: { root.clearKeyboard(); probe.kill(); } }
}

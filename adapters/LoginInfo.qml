import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower

// Read-only login/lock information. No session, authentication or power actions.
// Under Hyprland, queries hyprctl for layout and Caps Lock; under Cage/other
// Wayland hosts (e.g. greetd), falls back to standard Linux sysfs LEDs.
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
        if (!active) return;
        if (hyprland) refresh.restart();
        else sysfsRefresh.restart();
    }
    onActiveChanged: {
        clearKeyboard();
        if (active) refreshKeyboard();
        else { refresh.stop(); sysfsRefresh.stop(); if (probe.running) probe.kill(); }
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

    // Non-Hyprland fallback (Cage greeter, Sway, etc.): inspect Linux Caps Lock LEDs directly.
    FolderListModel {
        id: ledsFolder
        folder: root.active && !root.hyprland ? "file:///sys/class/leds" : ""
        nameFilters: ["*capslock*"]
        showDirs: true
        showFiles: false
        showDotAndDotDot: false
        onStatusChanged: if (status === FolderListModel.Ready && root.active && !root.hyprland) sysfsRefresh.restart()
    }
    Component {
        id: ledReader
        FileView {
            id: view
            property string ledPath: ""
            path: ledPath
            printErrors: false
            onLoaded: {
                if (root.active && !root.hyprland && text().trim() !== "0" && text().trim() !== "")
                    root.capsLock = true;
                view.destroy();
            }
            onLoadFailed: view.destroy()
        }
    }
    Timer {
        id: sysfsRefresh
        interval: 60
        onTriggered: {
            if (!root.active || root.hyprland) return;
            root.capsLock = false;
            for (let i = 0; i < ledsFolder.count; i++) {
                let dir = ledsFolder.get(i, "filePath");
                if (dir.startsWith("file://")) dir = dir.slice(7);
                ledReader.createObject(root, {ledPath: dir + "/brightness"});
            }
        }
    }
}

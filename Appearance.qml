pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "components/HyprlandControlCommands.js" as Commands

// Publish the manual preference through GTK Settings portal and Hyprland.
Scope {
    id: root
    property string mode: ""
    property string compositorError: ""
    property string preferenceError: ""
    readonly property string error: preferenceError || compositorError
    property string appliedPreference: ""
    property string applyingPreference: ""
    property string applyingMode: ""
    property string appliedMode: ""
    property int compositorGeneration: 0
    property int applyingGeneration: 0

    onModeChanged: Qt.callLater(apply)

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "configreloaded") return;
            // Reload restores the disk snapshot, which can lag a live mode
            // change or be stale after a failed save. Reassert observed state.
            root.compositorGeneration++;
            root.appliedMode = "";
            Qt.callLater(root.apply);
        }
    }

    function apply() {
        if (mode !== "dark" && mode !== "light") return;
        if (!preference.running && mode !== appliedPreference) {
            applyingPreference = mode;
            preference.command = ["gsettings", "set", "org.gnome.desktop.interface",
                "color-scheme", mode === "dark" ? "prefer-dark" : "prefer-light"];
            preference.running = true;
        }
        if (update.running || mode === appliedMode || !Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) return;
        applyingMode = mode;
        applyingGeneration = compositorGeneration;
        compositorError = "";
        update.command = ["hyprctl", "eval",
            "dofile(" + Commands.luaString(Quickshell.shellPath("adapters/Hyprland.lua")) + ").apply('" + applyingMode + "')"];
        update.running = true;
    }

    Process {
        id: preference
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) console.warn("Appearance preference:", text.trim())
        }
        onExited: (code, status) => {
            if (code === 0 && status === 0) {
                root.appliedPreference = root.applyingPreference;
                root.preferenceError = "";
            } else root.preferenceError = "Could not publish application colour preference";
            if (root.mode !== root.applyingPreference) Qt.callLater(root.apply);
        }
    }

    Process {
        id: update
        stderr: StdioCollector {
            onStreamFinished: { if (text.trim()) console.warn("Hyprland appearance:", text.trim()); }
        }
        onExited: (code, status) => {
            if (code !== 0 || status !== 0) {
                root.compositorError = "Hyprland colour update failed (" + code + ")";
                console.error(root.compositorError);
            } else if (root.applyingGeneration === root.compositorGeneration) {
                root.appliedMode = root.applyingMode;
            }
            // Coalesce rapid changes, then apply the newest shell mode.
            if (root.mode !== root.applyingMode
                    || root.applyingGeneration !== root.compositorGeneration)
                Qt.callLater(root.apply);
        }
    }
}

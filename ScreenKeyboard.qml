pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root
    required property Theme style
    property string executable: ""
    readonly property bool available: executable !== ""
    property bool shown: false
    property bool pending: false
    property bool requestedShown: false
    property string error: ""
    signal feedback(string key, string summary, string body, bool critical)

    function fail(message) {
        error = message;
        feedback("screen-keyboard", "Screen keyboard", message, false);
    }

    function colorArgument(color) { return String(color).slice(1); }
    function toggle() {
        if (!available || pending) return false;
        error = "";
        requestedShown = !shown;
        pending = true;
        deadline.restart();
        if (!keyboard.running) {
            keyboard.command = [executable, "-H", "280", "-L", "240", "--no-popup",
                "--bg", colorArgument(style.panelSurface),
                "--fg", colorArgument(style.surfaceRaised),
                "--fg-sp", colorArgument(style.surfaceHover),
                "--text", colorArgument(style.textPrimary),
                "--text-sp", colorArgument(style.textPrimary),
                "--press", colorArgument(style.surfaceSelected),
                "--press-sp", colorArgument(style.surfaceSelected),
                "--text-press", colorArgument(style.textSelected),
                "--text-press-sp", colorArgument(style.textSelected)];
            keyboard.running = true;
        } else {
            // Linux SIGUSR1 hides; SIGUSR2 shows without taking keyboard focus.
            keyboard.signal(requestedShown ? 12 : 10);
        }
        refresh.restart();
        return true;
    }

    Process {
        id: probe
        // Probe once per shell load without starting a keyboard surface or a shell.
        command: ["wvkbd-mobintl", "-v"]
        running: true
        onExited: (code, status) => {
            root.executable = code === 0 && status === 0 ? "wvkbd-mobintl" : "";
        }
    }

    Process {
        id: keyboard
        onStarted: refresh.restart()
        onRunningChanged: {
            if (!running) {
                root.shown = false;
            }
        }
        onExited: (code, status) => {
            root.pending = false;
            deadline.stop();
            if (code !== 0 || status !== 0) root.fail("Screen keyboard stopped unexpectedly.");
        }
        stderr: StdioCollector {
            onStreamFinished: { if (text.trim()) console.warn("Screen keyboard:", text.trim()); }
        }
    }

    // The keyboard's own hide key unmaps its layer without exiting. Observe the
    // compositor's actual surface, not just whether the child process is alive.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (keyboard.running && (event.name === "openlayer" || event.name === "closelayer")
                    && event.data === "wvkbd") refresh.restart();
        }
    }
    Timer {
        id: refresh
        interval: 80
        onTriggered: {
            if (!keyboard.running) return;
            if (layers.running) restart();
            else layers.running = true;
        }
    }
    Process {
        id: layers
        command: ["hyprctl", "-j", "layers"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!keyboard.running) return;
                try {
                    const monitors = JSON.parse(text);
                    root.shown = Object.values(monitors).some(monitor =>
                        Object.values(monitor.levels ?? {}).some(level => level.some(layer =>
                            layer.namespace === "wvkbd" && layer.pid === keyboard.processId
                            && layer.w > 1 && layer.h > 1)));
                    if (root.pending && root.shown === root.requestedShown) {
                        root.pending = false;
                        deadline.stop();
                    }
                } catch (error) { console.warn("Screen keyboard visibility:", error); }
            }
        }
    }
    Timer {
        id: deadline
        interval: 3000
        onTriggered: {
            root.pending = false;
            if (root.shown !== root.requestedShown)
                root.fail("Screen keyboard did not respond. Try again.");
        }
    }
}

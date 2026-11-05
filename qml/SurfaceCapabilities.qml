import QtQuick
import Quickshell
import Quickshell.Io

// Fail closed: only the supported Hyprland adapter can enable desktop glass.
// BackgroundEffect currently exposes no portable capability/acceptance signal.
Scope {
    id: root
    property bool blurAvailable: false
    property bool enabled: true
    function refresh() {
        if (!enabled || !Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) {
            blurAvailable = false;
            return;
        }
        if (!probe.running) probe.running = true;
    }
    Component.onCompleted: refresh()
    Process {
        id: probe
        command: ["hyprctl", "-j", "getoption", "decoration:blur:enabled"]
        property bool result: false
        onStarted: { result = false; deadline.restart(); }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const option = JSON.parse(text);
                    probe.result = option.option === "decoration:blur:enabled" && option.bool === true;
                } catch (_) { probe.result = false; }
            }
        }
        onExited: (code, status) => {
            deadline.stop();
            root.blurAvailable = code === 0 && status === 0 && result;
        }
    }
    Timer {
        id: deadline
        interval: 1500
        onTriggered: { root.blurAvailable = false; probe.signal(9); }
    }
}

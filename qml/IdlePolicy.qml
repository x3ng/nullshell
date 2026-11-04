import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    required property bool keepAwake
    required property bool ready
    required property var deadlines
    property bool dimmed: false
    property bool displayOff: false

    function run(command) {
        Quickshell.execDetached(command);
    }

    function setDimmed(value) {
        if (dimmed === value) return;
        dimmed = value;
        run(value
            ? ["brightnessctl", "--class=backlight", "--save", "set", "10%"]
            : ["brightnessctl", "--class=backlight", "--restore"]);
    }

    function setDisplayOff(value) {
        if (displayOff === value) return;
        displayOff = value;
        run(["hyprctl", "dispatch", value
            ? "hl.dsp.dpms({action = \"off\"})"
            : "hl.dsp.dpms({action = \"on\"})"]);
    }

    // A shell reload/exit must not leave a dimmed backlight or powered-off output.
    Component.onDestruction: {
        setDimmed(false);
        setDisplayOff(false);
    }

    onKeepAwakeChanged: {
        if (keepAwake) {
            setDimmed(false);
            setDisplayOff(false);
        }
    }

    IdleMonitor {
        timeout: root.deadlines.dimSeconds
        enabled: root.ready && !root.keepAwake
        respectInhibitors: true
        onIsIdleChanged: root.setDimmed(isIdle)
    }

    IdleMonitor {
        timeout: root.deadlines.lockSeconds
        enabled: root.ready && !root.keepAwake
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle) root.run(["qs-lock"]);
        }
    }

    IdleMonitor {
        timeout: root.deadlines.displayOffSeconds
        enabled: root.ready && !root.keepAwake
        respectInhibitors: true
        onIsIdleChanged: root.setDisplayOff(isIdle)
    }
}

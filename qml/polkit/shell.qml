import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Polkit

ShellRoot {
    id: root
    Component.onCompleted: Quickshell.watchFiles = false
    Theme { id: style; darkMode: appearance.text().trim() !== "light" }
    FileView {
        id: appearance
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/nullshell/appearance-mode"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    PolkitAgent {
        id: agent
        onAuthenticationRequestStarted: {
            prompt.screen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) || Quickshell.screens[0];
            Qt.callLater(view.resetInput);
        }
        onIsActiveChanged: if (!isActive) view.resetInput()
    }
    PanelWindow {
        id: prompt
        visible: agent.isActive
        implicitWidth: Math.min(480, (screen?.width || 1920) - 32)
        implicitHeight: Math.min(view.implicitHeight, (screen?.height || 1080) - 32)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:polkit"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        onVisibleChanged: if (visible) Qt.callLater(view.resetInput)
        Flickable {
            anchors.fill: parent
            contentHeight: view.implicitHeight
            clip: true
            AuthView {
                id: view
                width: parent.width
                height: implicitHeight
                theme: style
                flow: agent.flow
            }
        }
    }
    IpcHandler {
        target: "polkit"
        function status(): string {
            return JSON.stringify({registered: agent.isRegistered, active: agent.isActive});
        }
    }
    // Registration errors should be visible to systemd rather than silently
    // leaving a healthy-looking process with no functional agent.
    Timer {
        interval: 5000
        running: true
        onTriggered: if (!agent.isRegistered) {
            console.error("Polkit agent registration failed");
            Qt.exit(1);
        }
    }
}

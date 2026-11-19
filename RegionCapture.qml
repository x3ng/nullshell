import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: capture
    required property bool panelVisible
    property bool pending: false
    signal hidePanel()
    signal failed(string reason)

    function request() {
        if (pending) return false;
        pending = true;
        hidePanel();
        Qt.callLater(startWhenHidden);
        return true;
    }
    function startWhenHidden() {
        if (!pending || panelVisible || picker.running) return;
        picker.stdinEnabled = true;
        picker.running = true;
    }
    onPanelVisibleChanged: if (!panelVisible && pending) Qt.callLater(startWhenHidden)

    Process {
        id: picker
        property bool hasStarted: false
        command: ["slurp"]
        environment: ({LC_ALL: "C"})
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onStarted: {
            hasStarted = true;
            // The region picker takes input from the compositor. Send EOF on its pipe.
            stdinEnabled = false;
        }
        onRunningChanged: if (!running && !hasStarted && capture.pending) {
            capture.pending = false;
            capture.failed("Could not start the screenshot tool.");
        }
        onExited: (code, status) => {
            capture.pending = false;
            hasStarted = false;
            const reason = errors.text.trim();
            if (status === 0 && code !== 0 && reason === "selection cancelled") return;
            const geometry = output.text.trim();
            if (code !== 0 || status !== 0 || !geometry) {
                capture.failed(reason || "Could not select a screenshot region.");
                return;
            }
            editorProcess.createObject(capture, {geometry: geometry});
        }
    }

    Component {
        id: editorProcess
        Process {
            required property string geometry
            command: ["bash", Quickshell.shellPath("adapters/edit-region.sh"), geometry]
            stderr: StdioCollector { id: diagnostics }
            running: true
            onExited: (code, status) => {
                if (code !== 0 || status !== 0)
                    capture.failed(diagnostics.text.trim() || "Could not edit the screenshot.");
                destroy();
            }
        }
    }
}

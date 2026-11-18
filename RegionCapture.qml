import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: capture
    required property bool panelVisible
    property bool pending: false
    signal hidePanel()
    signal failed(string reason)
    signal saved(string path)

    function request() {
        if (pending) return false;
        pending = true;
        hidePanel();
        Qt.callLater(startWhenHidden);
        return true;
    }
    function startWhenHidden() {
        if (pending && !panelVisible && !picker.running) picker.running = true;
    }
    onPanelVisibleChanged: if (!panelVisible && pending) Qt.callLater(startWhenHidden)

    Process {
        id: picker
        property bool hasStarted: false
        command: ["nullshell", "capture-region"]
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onStarted: hasStarted = true
        onRunningChanged: if (!running && !hasStarted && capture.pending) {
            capture.pending = false;
            capture.failed("Could not start the screenshot tool.");
        }
        onExited: (code, status) => {
            capture.pending = false;
            hasStarted = false;
            if (code === 2 && status === 0) return;
            const path = output.text.replace(/\n$/, "");
            if (code === 0 && status === 0 && path.startsWith("/")) capture.saved(path);
            else capture.failed(errors.text.trim() || "The screenshot tool did not save an image.");
        }
    }
}

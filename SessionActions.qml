pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Session commands and logind capability discovery; no UI or confirmation policy.
Scope {
    id: session
    property var capabilities: ({suspend: false, reboot: false, poweroff: false})
    property bool useUwsm: false
    readonly property string sessionId: Quickshell.env("XDG_SESSION_ID")
    property bool busy: false
    property string error: ""
    property string requestedAction: ""
    property int probeIndex: 0
    readonly property var probes: [
        {action: "suspend", method: "CanSuspend"},
        {action: "reboot", method: "CanReboot"},
        {action: "poweroff", method: "CanPowerOff"}
    ]
    signal accepted(string action)

    function available(action) {
        return !busy && (action === "logout" ? useUwsm || sessionId !== "" : capabilities[action] === true);
    }
    function refresh() {
        if (probe.running || busy) return;
        probeIndex = 0;
        probe.running = true;
        if (!uwsmProbe.running) uwsmProbe.running = true;
    }
    function execute(action) {
        if (!available(action)) return false;
        if (!["suspend", "logout", "reboot", "poweroff"].includes(action)) return false;
        error = "";
        busy = true;
        requestedAction = action;
        operation.command = action === "logout"
            ? (useUwsm ? ["uwsm", "stop"] : ["loginctl", "terminate-session", sessionId])
            : ["systemctl", "--no-ask-password", "--no-block", action];
        operation.running = true;
        return true;
    }
    Component.onCompleted: refresh()
    Process {
        id: probe
        command: ["busctl", "--system", "--json=short", "--timeout=3s", "call",
            "org.freedesktop.login1", "/org/freedesktop/login1",
            "org.freedesktop.login1.Manager", session.probes[session.probeIndex].method]
        stdout: StdioCollector { id: probeOutput }
        onExited: (code, status) => {
            let permission = "no";
            try { permission = JSON.parse(probeOutput.text).data[0]; } catch (_) {}
            const updated = Object.assign({}, session.capabilities);
            updated[session.probes[session.probeIndex].action] = code === 0 && status === 0
                && ["yes", "challenge"].includes(permission);
            session.capabilities = updated;
            if (session.probeIndex < session.probes.length - 1) {
                session.probeIndex++;
                Qt.callLater(() => { probe.running = true; });
            }
        }
    }
    Process {
        id: uwsmProbe
        command: ["uwsm", "check", "is-active"]
        onExited: (code, status) => { session.useUwsm = code === 0 && status === 0; }
    }
    Process {
        id: operation
        stderr: StdioCollector { id: operationError }
        onExited: (code, status) => {
            session.busy = false;
            if (code === 0 && status === 0) session.accepted(session.requestedAction);
            else session.error = session.error || operationError.text.trim() || "The session action could not be started.";
        }
    }
    Timer {
        interval: 10000
        running: session.busy
        onTriggered: {
            session.error = "The session action did not respond. Please try again.";
            if (operation.running) operation.kill();
            else session.busy = false;
        }
    }
    Timer { interval: 5000; running: probe.running; onTriggered: probe.kill() }
    Timer { interval: 5000; running: uwsmProbe.running; onTriggered: uwsmProbe.kill() }
}

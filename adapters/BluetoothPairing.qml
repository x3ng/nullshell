pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Owns only the helper conversation. Device discovery, trust and connection
// policy belong to SystemControls; this adapter never invokes native actions.
Scope {
    id: root
    readonly property var device: state.device
    readonly property string prompt: state.prompt
    readonly property string code: state.code
    readonly property bool busy: state.device !== null || agent.running
    signal finished(var device, bool success, string error)

    QtObject {
        id: state
        property var device: null
        property string prompt: ""
        property string code: ""
        property int requestId: 0
    }

    function clearPrompt() {
        state.requestId = 0;
        state.code = "";
        state.prompt = "";
    }
    function finish(success, error) {
        if (!state.device) return;
        const completedDevice = state.device;
        state.device = null;
        clearPrompt();
        deadline.stop();
        startupCheck.stop();
        finished(completedDevice, success, error);
    }
    function start(device) {
        if (!device || busy) return false;
        clearPrompt();
        state.device = device;
        // Freeze argv for this invocation, independently of native object changes.
        agent.command = ["nullshell-helper", "bluetooth-agent", device.address, device.adapter.adapterId];
        agent.hasStarted = false;
        deadline.restart();
        startupCheck.restart();
        agent.running = true;
        return true;
    }
    function handleEvent(event) {
        if (!state.device || !event || event.version !== 1) return;
        if (event.type === "prompt") {
            if (!["confirm", "authorize", "pin", "passkey", "display"].includes(event.kind)
                    || !Number.isInteger(event.id) || event.id < 0
                    || (event.kind !== "display" && event.id === 0)
                    || typeof event.code !== "string") return;
            state.requestId = event.id;
            state.code = event.code;
            state.prompt = event.kind;
        } else if (event.type === "cancelled") {
            // Cancelling a prompt is not a terminal pairing result.
            clearPrompt();
        } else if (event.type === "done" && typeof event.success === "boolean") {
            finish(event.success, event.success ? "" : typeof event.error === "string" && event.error
                ? event.error : "Pairing failed. Try again with the device in pairing mode.");
        }
    }
    function answer(answer) {
        if (!state.device || !agent.running || !["confirm", "authorize", "pin", "passkey"].includes(state.prompt)) return false;
        if (typeof answer !== "string") return false;
        if (["confirm", "authorize"].includes(state.prompt) && !["yes", "no"].includes(answer)) return false;
        if (state.prompt === "passkey" && !/^[0-9]{1,6}$/.test(answer)) return false;
        if (state.prompt === "pin" && (!answer || answer.length > 16 || /[\x00-\x1f\x7f]/.test(answer))) return false;
        agent.write(JSON.stringify({version: 1, id: state.requestId, answer: answer}) + "\n");
        clearPrompt();
        return true;
    }
    function cancel() {
        if (!state.device) return false;
        state.device = null;
        clearPrompt();
        deadline.stop();
        startupCheck.stop();
        if (agent.running) {
            agent.write('{"version":1,"cancel":true}\n');
            cancellationDeadline.restart();
        }
        return true;
    }

    Process {
        id: agent
        property bool hasStarted: false
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                let event;
                try { event = JSON.parse(data); } catch (_) { return; }
                root.handleEvent(event);
            }
        }
        onStarted: hasStarted = true
        onExited: (exitCode, status) => {
            cancellationDeadline.stop();
            root.finish(false, "Pairing agent stopped. Try again.");
        }
    }
    Timer {
        id: startupCheck
        interval: 1000
        onTriggered: {
            if (root.device && !agent.running && !agent.hasStarted)
                root.finish(false, "Cannot start pairing. Check that nullshell-helper is installed.");
        }
    }
    Timer {
        id: deadline
        interval: 95000
        onTriggered: {
            root.finish(false, "Pairing agent did not respond. Try again.");
            agent.running = false;
        }
    }
    Timer {
        id: cancellationDeadline
        // Helper cleanup has two bounded two-second D-Bus calls. Keep the
        // process busy until it exits; kill only if cancellation gets stuck.
        interval: 6000
        onTriggered: agent.running = false
    }
}

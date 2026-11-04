pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "components/HyprlandControlCommands.js" as Commands

// Views select explicit workspace addresses and window addresses. Opening the panel
// must never redirect an operation to whichever window happens to be focused.
Scope {
    id: root
    required property var layoutState
    readonly property bool available: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    property var pendingOperation: null
    readonly property bool busy: pendingOperation !== null
    property int requestSequence: 0
    readonly property int lastRequestId: requestSequence
    property string error: ""
    signal feedback(string key, string summary, string body, bool critical)
    signal operationFinished(bool success, string operation, string target, int requestId, string message)
    readonly property string focusedWorkspaceAddress: Hyprland.focusedMonitor?.lastIpcObject.specialWorkspace?.address
        || Hyprland.focusedWorkspace?.address || ""
    property var workspaces: []
    property var windows: []
    // Snapshot native data, then publish outside the compositor's removal
    // signal stack. Qt must not rebuild nested delegates during QObject removal.
    onWorkspaceSnapshotChanged: publishDelay.restart()
    onWindowSnapshotChanged: publishDelay.restart()
    Component.onCompleted: publishDelay.restart()
    Timer {
        id: publishDelay
        interval: 0
        onTriggered: {
            if (JSON.stringify(root.workspaces) !== JSON.stringify(root.workspaceSnapshot)) root.workspaces = root.workspaceSnapshot;
            if (JSON.stringify(root.windows) !== JSON.stringify(root.windowSnapshot)) root.windows = root.windowSnapshot;
        }
    }
    readonly property var workspaceSnapshot: {
        const rows = Hyprland.workspaces.values.map(workspace => ({
            address: workspace.address,
            name: workspace.name,
            monitor: workspace.monitor?.name ?? "",
            active: workspace.active || workspace.address === root.focusedWorkspaceAddress,
            special: workspace.address.startsWith("special:"),
            exists: true,
            layout: root.layoutState.layouts[workspace.address] ?? "—",
            windowCount: workspace.toplevels.values.length
        }));
        return rows.sort((a, b) => Commands.compareWorkspaces(a, b));
    }
    readonly property var workspaceTargets: {
        const rows = workspaces.slice();
        if (root.available) {
            for (let id = 1; id <= 10; id++) {
                if (rows.some(row => row.address === String(id))) continue;
                rows.push({address: String(id), name: String(id), monitor: "",
                    active: false, special: false, exists: false, layout: "—", windowCount: 0});
            }
        }
        return rows.sort((a, b) => Commands.compareWorkspaces(a, b));
    }
    readonly property var windowSnapshot: Hyprland.toplevels.values
        .filter(window => window.lastIpcObject.mapped !== false && Commands.address(window.address))
        .map(window => ({
            address: Commands.address(window.address),
            title: window.title || window.lastIpcObject.title || "Untitled window",
            appId: window.wayland?.appId || window.lastIpcObject.class || window.lastIpcObject.initialClass || "",
            workspaceAddress: window.workspace?.address ?? window.lastIpcObject.workspace?.address ?? "",
            workspaceName: window.workspace?.name ?? window.lastIpcObject.workspace?.name ?? "",
            monitor: window.monitor?.name ?? "",
            floating: !!window.lastIpcObject.floating,
            fullscreen: Number(window.lastIpcObject.fullscreen ?? 0) !== 0,
            focused: window.activated
        })).sort((a, b) => Commands.compareWorkspaceAddresses(a.workspaceAddress, b.workspaceAddress) || a.address.localeCompare(b.address))

    function reject(message) {
        error = message;
        feedback("desktop-operation", "Desktop operation", message, false);
        return false;
    }
    function run(request, operation, target) {
        if (busy) return reject("Another desktop operation is still running");
        if (!available) return reject("Hyprland is not available");
        if (request.error) return reject(request.error);
        error = "";
        requestSequence++;
        const context = {id: requestSequence, operation: operation, target: String(target)};
        pendingOperation = context;
        const process = actionFactory.createObject(root, {context: context, code: request.code});
        if (!process) {
            finish(context, false, "Could not start desktop operation");
            return false;
        }
        process.running = true;
        return true;
    }
    function workspaceRow(address) { return workspaceTargets.find(row => row.address === address); }
    function windowRequest(operation, address, workspaceAddress) {
        const target = Commands.address(address);
        const window = target ? windows.find(row => row.address === target) : null;
        const names = {focus: "focusWindow", float: "toggleFloat", fullscreen: "toggleFullscreen",
            move: "moveWindow", close: "closeWindow"};
        return run(Commands.windowAction(operation, window, workspaceRow(workspaceAddress)), names[operation], target);
    }
    function focusWorkspace(address) { return run(Commands.workspaceAction("focus", workspaceRow(address)), "focusWorkspace", address); }
    function setLayout(address, layout) { return run(Commands.workspaceAction("layout", workspaceRow(address), layout), "setLayout", address); }
    function focusWindow(address) { return windowRequest("focus", address); }
    function toggleFloat(address) { return windowRequest("float", address); }
    function toggleFullscreen(address) { return windowRequest("fullscreen", address); }
    function moveWindow(address, workspaceAddress) { return windowRequest("move", address, workspaceAddress); }
    function closeWindow(address) { return windowRequest("close", address); }
    function lock() {
        // Acknowledge launch; the separate Quickshell locker owns the session lock and PAM.
        return run({code: Commands.result("hl.dsp.exec_cmd('qs-lock')")}, "lock", "session");
    }
    function refresh() {
        if (!available) return;
        Hyprland.refreshToplevels();
        Hyprland.refreshMonitors();
        layoutState.refresh();
    }
    function finish(context, success, message) {
        // A timed-out old process can exit after a newer request was accepted.
        if (!pendingOperation || pendingOperation.id !== context.id) return;
        pendingOperation = null;
        error = success ? "" : message || "Desktop operation failed";
        if (!success) feedback("desktop-operation", "Desktop operation", error, false);
        refresh();
        operationFinished(success, context.operation, context.target, context.id, success ? "" : error);
    }
    Component {
        id: actionFactory
        Process {
            id: action
            required property var context
            required property string code
            property bool hasStarted: false
            property bool settled: false
            property string output: ""
            property string failure: ""
            // eval discards Lua return values; repl preserves our explicit result.
            command: ["hyprctl", "repl", code]
            stdout: StdioCollector { onStreamFinished: action.output = text.trim() }
            stderr: StdioCollector { onStreamFinished: action.failure = text.trim() }
            function settle(success, message) {
                if (settled) return;
                settled = true;
                root.finish(context, success, message);
                running = false;
                destroy();
            }
            onStarted: hasStarted = true
            onExited: (exitCode, status) => {
                const success = exitCode === 0 && status === 0 && output === "OK";
                settle(success, output.startsWith("ERROR: ") ? output.slice(7)
                    : failure || output || "Desktop operation failed (" + exitCode + ")");
            }
            // Quickshell 0.3.2 does not emit exited when executable startup fails.
            property Timer startupCheck: Timer {
                interval: 1000
                running: true
                onTriggered: {
                    if (!action.hasStarted && !action.running)
                        action.settle(false, "Could not start hyprctl");
                }
            }
            property Timer deadline: Timer {
                interval: 8000
                running: true
                onTriggered: action.settle(false, "Desktop operation timed out")
            }
        }
    }
}

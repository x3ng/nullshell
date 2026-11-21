pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "components/HyprlandControlCommands.js" as Commands

// Single writer, opt-in only. Hyprland's own configuration remains the safe
// layout and can be restored even if the desktop stops during a trial.
Scope {
    id: root
    property string mode: "off"
    property string file: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
        + "/nullshell/display-profiles.json"
    readonly property bool enabled: mode !== "off" && !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    property string phase: "idle"
    property string error: ""
    property string active: ""
    property var inventory: null
    property string lastAutoTopology: ""
    property string pendingName: ""
    property string trialTopology: ""
    property string fingerprint: ""
    property bool automaticTrial: false
    property var layout: null
    property string token: ""
    property int checks: 0
    property bool verified: false
    property bool scanAgain: false
    readonly property string luaModule: "dofile(" + Commands.luaString(Quickshell.shellPath("adapters/DisplayTrial.lua")) + ")"

    function status(): string {
        return JSON.stringify({mode: mode, enabled: enabled, phase: phase, error: error, active: active,
            pending: layout?.name ?? "", verified: verified,
            profiles: inventory?.profiles ?? [], compatible: inventory?.compatible ?? [],
            suggested: inventory?.layout?.name ?? ""});
    }

    onEnabledChanged: {
        if (enabled) scheduleScan();
        else if (active || ["baseline", "recheck", "apply", "preview", "confirm"].includes(phase)) queueRevert();
        else if (["scan", "adopt", "adopt-check"].includes(phase)) idle();
    }
    onModeChanged: {
        lastAutoTopology = "";
        Qt.callLater(scheduleScan);
    }
    Component.onCompleted: if (enabled) debounce.restart()

    function scheduleScan() {
        if (enabled) debounce.restart();
    }

    function outputsChanged() {
        if (phase === "preview") {
            verified = false;
            verifyAgain.restart();
        }
        scheduleScan();
    }

    function scan(name) {
        if (!enabled || phase !== "idle" || planner.running) return false;
        pendingName = name;
        phase = "scan";
        startPlan(name);
        return true;
    }

    function startPlan(name) {
        planner.command = ["nullshell-helper", "displays", "plan", file].concat(name ? [name] : []);
        planner.running = true;
    }

    function activate(name): bool {
        if (!name || name.length > 80 || !enabled) return false;
        return scan(name);
    }

    function confirm(): bool {
        if (phase !== "preview" || !verified || executor.running) return false;
        phase = "confirm";
        execute(["eval", luaModule + ".confirm(" + Commands.luaString(token) + ")"]);
        return true;
    }

    function revert(): bool {
        if (phase !== "preview" && !(phase === "idle" && enabled)) return false;
        queueRevert();
        return true;
    }

    function queueRevert() {
        verifyAgain.stop();
        previewDeadline.stop();
        layout = null;
        verified = false;
        active = "";
        phase = "revert";
        if (!executor.running) execute(["reload"]);
    }

    function idle() {
        phase = "idle";
        layout = null;
        verified = false;
        if (scanAgain) {
            scanAgain = false;
            scheduleScan();
        }
    }

    function execute(args) {
        executor.command = ["hyprctl"].concat(args);
        executor.running = true;
        executeDeadline.restart();
    }

    function startTrial() {
        token = String(Date.now()) + "-" + Math.floor(Math.random() * 1000000);
        phase = "apply";
        execute(["eval", luaModule + ".start(" + Commands.luaString(token) + ", "
            + Commands.luaString(fingerprint) + ", function()\n" + layout.lua + "\nend)"]);
    }

    function startBaseline() {
        // Clear old overrides first, including workspace assignments and mirrors.
        active = "";
        phase = "baseline";
        execute(["reload"]);
    }

    function liveMatches(items) {
        if (!Array.isArray(items) || items.length !== layout.expected.length) return false;
        const topology = {};
        for (const item of items.slice().sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)) {
            topology[item.name] = ([item.make, item.model, item.serial].map(x => String(x ?? "").trim())
                .filter(x => x).join("|") || item.name).toLowerCase();
        }
        if (JSON.stringify(topology) !== trialTopology) return false;
        return layout.expected.every(e => {
            const actual = items.find(o => o.name === e.name);
            if (!actual || actual.disabled !== !e.enabled) return false;
            if (!e.enabled) return true;
            if (e.mirror) {
                const source = items.find(o => o.name === e.mirror);
                return actual.mirrorOf === e.mirror
                    || (source && source.id !== undefined && String(actual.mirrorOf) === String(source.id));
            }
            const resolutionMatches = actual.width === e.width && actual.height === e.height
                || (e.transform % 2 === 1 && actual.width === e.height && actual.height === e.width);
            return resolutionMatches && (actual.mirrorOf == null || actual.mirrorOf === "none" || String(actual.mirrorOf) === "-1")
                && actual.x === e.x && actual.y === e.y && actual.transform === e.transform
                && Math.abs(actual.scale - e.scale) < 0.015 && Math.abs(actual.refreshRate - e.refresh) < 0.2;
        });
    }

    Connections {
        target: Hyprland
        enabled: root.enabled
        function onRawEvent(event) {
            if (event.name === "configreloaded" && root.phase === "idle" && root.active) {
                root.active = "";
                root.lastAutoTopology = "";
                if (root.mode === "manual") return;
            }
            if (event.name.startsWith("monitoradded") || event.name.startsWith("monitorremoved")) root.outputsChanged();
            else if (event.name === "configreloaded") root.scheduleScan();
        }
    }

    Connections {
        target: Quickshell
        enabled: root.enabled
        function onScreensChanged() { root.outputsChanged(); }
    }

    FileView {
        id: profileFile
        path: root.enabled ? root.file : ""
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload();
            root.lastAutoTopology = "";
            root.scheduleScan();
        }
    }

    Timer {
        id: debounce
        interval: 450
        onTriggered: if (!root.scan("")) root.scanAgain = root.enabled
    }
    Timer {
        id: executeDeadline
        interval: 3500
        onTriggered: {
            executor.running = false;
            root.error = "Could not communicate with Hyprland";
            // The compositor's trial timer, if installed, still owns rollback.
            root.active = "";
            root.idle();
        }
    }
    Timer {
        id: verifyAgain
        interval: 350
        onTriggered: if (root.phase === "preview" && !readback.running) readback.running = true
    }
    Timer {
        id: previewDeadline
        interval: 14000
        onTriggered: {
            if (root.phase !== "preview") return;
            root.error = "Display trial was not confirmed; reverting to Hyprland configuration";
            root.queueRevert();
        }
    }

    Process {
        id: planner
        stdout: StdioCollector { id: planOutput }
        stderr: StdioCollector { id: planError }
        onExited: (code, status) => {
            if (root.phase !== "scan" && root.phase !== "recheck") return;
            if (!root.enabled) { root.idle(); return; }
            try {
                if (code !== 0 || status !== 0) throw new Error(planError.text.trim() || "Display planner unavailable");
                const result = JSON.parse(planOutput.text);
                if (result.version !== 1) throw new Error("Incompatible display planner");
                root.inventory = result;
                const fingerprint = JSON.stringify(result.topology);
                if (root.phase === "recheck") {
                    if (fingerprint !== root.trialTopology || result.layout?.lua !== root.layout.lua) {
                        root.error = "Display outputs or profile changed while preparing the layout";
                        root.idle(); // the known Hyprland baseline is already loaded
                        root.scheduleScan();
                    } else root.startTrial();
                    return;
                }
                const explicit = root.pendingName !== "";
                if (!explicit && (root.mode !== "auto" || root.lastAutoTopology === fingerprint)) { root.idle(); return; }
                if (!result.layout) {
                    if (!explicit) root.lastAutoTopology = fingerprint;
                    root.error = explicit ? "Profile does not match the connected displays"
                        : result.compatible.length ? "Multiple display profiles match; select one manually" : "No profile matches the connected displays";
                    if (root.active && !explicit) root.queueRevert();
                    else root.idle();
                    return;
                }
                root.error = "";
                root.lastAutoTopology = fingerprint;
                root.automaticTrial = !explicit;
                root.layout = result.layout;
                root.trialTopology = fingerprint;
                root.fingerprint = Qt.md5(JSON.stringify([fingerprint, result.layout.name, result.layout.lua]));
                if (explicit) root.startBaseline();
                else {
                    root.phase = "adopt";
                    root.execute(["eval", root.luaModule + ".is_active(" + Commands.luaString(root.fingerprint) + ")"]);
                }
            } catch (e) {
                root.error = String(e);
                root.idle();
            }
        }
    }
    Process {
        id: executor
        stdout: StdioCollector { id: executeOutput }
        onExited: (code, status) => {
            executeDeadline.stop();
            if (root.phase === "idle") return;
            const ok = code === 0 && status === 0 && executeOutput.text.trim() === "ok";
            if (root.phase === "adopt") {
                if (ok && !readback.running) {
                    root.phase = "adopt-check";
                    readback.running = true;
                } else root.startBaseline();
                return;
            }
            if (root.phase === "revert") {
                // A disabled mode may have requested rollback while eval was running.
                if (executor.command[1] !== "reload") { root.execute(["reload"]); return; }
                if (!ok) root.error = "Could not restore Hyprland configuration";
                root.idle();
                return;
            }
            if (!ok) {
                root.error = "Hyprland rejected the display operation: " + executeOutput.text.trim().slice(0, 400);
                root.queueRevert();
                return;
            }
            if (root.phase === "baseline") {
                root.phase = "recheck";
                root.startPlan(root.layout.name);
            } else if (root.phase === "apply") {
                root.phase = "preview";
                root.checks = 0;
                previewDeadline.restart();
                verifyAgain.restart();
            } else if (root.phase === "confirm") {
                previewDeadline.stop();
                root.active = root.layout.name;
                root.idle();
            }
        }
    }
    Process {
        id: readback
        command: ["hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector { id: readbackOutput }
        onExited: (code, status) => {
            if (root.phase !== "preview" && root.phase !== "adopt-check") return;
            let matches = false;
            if (code === 0 && status === 0) {
                try { matches = root.liveMatches(JSON.parse(readbackOutput.text)); } catch (_) {}
            }
            if (root.phase === "adopt-check") {
                if (matches) {
                    root.active = root.layout.name;
                    root.idle();
                } else root.startBaseline();
                return;
            }
            if (matches) {
                root.verified = true;
                if (root.automaticTrial) root.confirm();
                else {
                    root.checks = 0;
                    verifyAgain.restart();
                }
            } else if (++root.checks >= 8) {
                root.error = "Hyprland did not apply the requested display layout";
                root.queueRevert();
            } else {
                root.verified = false;
                verifyAgain.restart();
            }
        }
    }
}

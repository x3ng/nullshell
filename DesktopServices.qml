pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Mpris

Scope {
    id: root
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var battery: UPower.displayDevice
    readonly property var players: Mpris.players.values
    readonly property var player: players.find(p => p.isPlaying) ?? players[0] ?? null
    // Persisted user intent gates idle before the transient inhibitor starts.
    readonly property bool keepAwake: keepAwakeRequested || keepAwakeUntil > 0
    property double keepAwakeUntil: 0
    readonly property bool keepAwakeInhibitorActive: idleInhibitor.running
    property bool keepAwakeRequested: false
    property bool keepAwakeReady: false
    readonly property var source: Pipewire.defaultAudioSource
    signal feedback(string key, string summary, string body, bool critical)
    property bool controlsVisible: false
    property bool wifiDiscoveryActive: false
    readonly property var controls: systemControls
    property bool mixerVisible: false
    readonly property var audioStreams: mixerVisible ? Pipewire.nodes.values.filter(n => n.audio && n.isStream) : []
    readonly property var playbackStreams: audioStreams.filter(n => n.properties["media.class"] === "Stream/Output/Audio")
    PwObjectTracker { objects: root.audioStreams }
    readonly property var audioOutputs: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && n.isSink)
    readonly property var audioInputs: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && !n.isSink)

    SystemControls {
        id: systemControls
        active: root.controlsVisible
        wifiDiscoveryActive: root.wifiDiscoveryActive
    }

    // A systemd idle inhibitor survives closing the panel. Closing stdin
    // releases it normally; shell shutdown also closes the pipe to cat.
    Process {
        id: idleInhibitor
        command: ["systemd-inhibit", "--what=idle", "--mode=block",
            "--who=Quickshell", "--why=Keep screen awake", "cat"]
        stdinEnabled: true
        property string failure: ""
        property bool awaitingStart: false
        property bool startFailed: false
        onStarted: awaitingStart = false
        onRunningChanged: {
            // FailedToStart emits runningChanged but no exited signal. The
            // explicit attempt guard keeps initial construction silent.
            if (!running && awaitingStart) {
                awaitingStart = false;
                startFailed = true;
                root.feedback("keep-awake", "Could not keep the desktop awake",
                    "Could not start systemd-inhibit. Check that it is installed and executable.", false);
            }
        }
        stderr: StdioCollector { onStreamFinished: idleInhibitor.failure = text.trim() }
        onExited: (code, status) => {
            // Rapid off/on can arrive while the old cat is closing its stdin.
            if (root.keepAwake && code === 0 && status === 0)
                Qt.callLater(root.reconcileIdleInhibitor);
            if (!startFailed && (code !== 0 || status !== 0))
                root.feedback("keep-awake", "Could not keep the desktop awake",
                    failure || "The idle inhibitor stopped unexpectedly.", false);
        }
    }

    FileView {
        id: keepAwakeFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
            + "/nullshell/keep-awake"
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onSaveFailed: root.feedback("keep-awake-save", "Could not save Keep awake",
            "The current choice is active, but could not be saved for the next shell start.", false)
    }

    Component.onCompleted: {
        const saved = keepAwakeFile.text().trim();
        if (saved.startsWith("{")) {
            try {
                const state = JSON.parse(saved);
                if (state.version === 1) {
                    keepAwakeRequested = state.permanent === true;
                    if (Number.isSafeInteger(state.until) && state.until > Date.now())
                        keepAwakeUntil = state.until;
                }
            } catch (_) { feedback("keep-awake-save", "Invalid Keep awake state", "Idle behavior has been restored.", false); }
        } else keepAwakeRequested = saved === "true";
        keepAwakeReady = true;
        reconcileIdleInhibitor();
    }

    function reconcileIdleInhibitor() {
        if (!keepAwakeReady) return;
        if (!keepAwake) {
            idleInhibitor.stdinEnabled = false;
        } else if (!idleInhibitor.running) {
            idleInhibitor.stdinEnabled = true;
            idleInhibitor.failure = "";
            idleInhibitor.startFailed = false;
            idleInhibitor.awaitingStart = true;
            idleInhibitor.running = true;
        }
    }

    function setKeepAwake(value) {
        if (!keepAwakeReady) return false;
        keepAwakeRequested = value;
        if (!value) keepAwakeUntil = 0;
        saveKeepAwake();
        reconcileIdleInhibitor();
        return true;
    }

    function saveKeepAwake() {
        keepAwakeFile.setText((keepAwakeUntil ? JSON.stringify({version: 1, permanent: keepAwakeRequested, until: keepAwakeUntil})
            : String(keepAwakeRequested)) + "\n");
    }
    function keepAwakeFor(minutes) {
        if (!keepAwakeReady || !Number.isInteger(minutes) || minutes < 0 || minutes > 1440) return false;
        keepAwakeUntil = minutes ? Date.now() + minutes * 60000 : 0;
        saveKeepAwake();
        reconcileIdleInhibitor();
        return true;
    }
    Timer {
        interval: 1000
        running: root.keepAwakeUntil > 0
        repeat: true
        onTriggered: if (Date.now() >= root.keepAwakeUntil) root.keepAwakeFor(0)
    }
    function toggleKeepAwake() { return setKeepAwake(!keepAwake); }

    PwObjectTracker {
        objects: root.audioOutputs.concat(root.audioInputs)
    }

    function toggleMicMute() {
        var audio = Pipewire.defaultAudioSource?.audio;
        if (!audio) return false;
        audio.muted = !audio.muted;
        return true;
    }

    function toggleOutputMute() {
        if (!sink?.audio) return false;
        sink.audio.muted = !sink.audio.muted;
        return true;
    }

    function selectAudioDevice(node, input) {
        const devices = input ? audioInputs : audioOutputs;
        if (!devices.includes(node)) return false;
        if (input) Pipewire.preferredDefaultAudioSource = node;
        else Pipewire.preferredDefaultAudioSink = node;
        return true;
    }

    function setVolume(value) {
        var audio = Pipewire.defaultAudioSink?.audio;
        if (!audio || !Number.isFinite(value)) return false;
        audio.volume = Math.max(0, Math.min(1, value));
        return true;
    }

    function durationLabel(seconds) {
        if (!seconds || seconds <= 0) return "";
        var hours = Math.floor(seconds / 3600);
        var minutes = Math.floor((seconds % 3600) / 60);
        if (hours > 0) return hours + "H " + minutes + "M";
        return Math.max(1, minutes) + "M";
    }

    function batteryDetail(device) {
        if (!device) return "UNAVAILABLE";
        if (device.state === UPowerDeviceState.Charging) {
            var untilFull = durationLabel(device.timeToFull);
            return untilFull ? "CHARGING · " + untilFull + " TO FULL" : "CHARGING";
        }
        if (device.state === UPowerDeviceState.Discharging) {
            var remaining = durationLabel(device.timeToEmpty);
            return remaining ? "DISCHARGING · " + remaining + " LEFT" : "DISCHARGING";
        }
        if (device.state === UPowerDeviceState.FullyCharged) return "FULLY CHARGED";
        return "BATTERY";
    }

    // ── Brightness — event-driven via kernel uevent ─────────────────
    property real brightness: -1   // 0.0~1.0, -1 = not initialized
    readonly property bool brightnessSetting: brightnessWriteProc.running || pendingBrightness >= 0
    property int pendingBrightness: -1
    property int brightnessRevision: 0

    Process {
        id: brightnessReadProc
        property int revision: 0
        command: ["brightnessctl", "--class", "backlight", "--machine-readable"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                // brightnessctl's native CSV: device,class,current,percent,max.
                const fields = data.trim().split(",");
                const current = Number(fields[2]);
                const maximum = Number(fields[4]);
                if (!root.brightnessSetting && brightnessReadProc.revision === root.brightnessRevision
                        && fields.length >= 5
                        && Number.isFinite(current) && Number.isFinite(maximum) && maximum > 0)
                    root.brightness = Math.max(0, Math.min(1, current / maximum));
            }
        }
    }

    Process {
        id: brightnessWatcher
        command: ["udevadm", "monitor", "--subsystem-match=backlight", "--kernel"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                if (!root.brightnessSetting) brightnessDebounce.restart();
            }
        }
        // Also recover from a clean unexpected exit or failure to start.
        onRunningChanged: { if (!running) watcherRestart.restart(); }
    }
    Timer {
        id: watcherRestart
        interval: 2000
        onTriggered: brightnessWatcher.running = true
    }

    Timer {
        id: brightnessDebounce
        interval: 50
        onTriggered: {
            if (root.brightnessSetting || brightnessReadProc.running) restart();
            else {
                brightnessReadProc.revision = root.brightnessRevision;
                brightnessReadProc.running = true;
            }
        }
    }

    function setBrightness(value) {
        if (!Number.isFinite(value) || brightness < 0) return false;
        brightnessRevision++;
        value = Math.max(0, Math.min(1, value));
        pendingBrightness = Math.max(1, Math.round(value * 100));
        root.brightness = pendingBrightness / 100;
        Qt.callLater(flushBrightness);
        return true;
    }

    function flushBrightness() {
        if (brightnessWriteProc.running || pendingBrightness < 0) return;
        brightnessWriteProc.command = ["brightnessctl", "--class", "backlight",
            "set", pendingBrightness + "%", "--quiet"];
        pendingBrightness = -1;
        brightnessWriteProc.failure = "";
        brightnessWriteProc.startFailed = false;
        brightnessWriteProc.awaitingStart = true;
        brightnessWriteProc.running = true;
    }

    // Serialize writes and retain only the latest slider target. Read back the
    // hardware value after completion, including rejected/failed writes.
    Process {
        id: brightnessWriteProc
        property string failure: ""
        property bool awaitingStart: false
        property bool startFailed: false
        onStarted: awaitingStart = false
        stderr: StdioCollector { onStreamFinished: brightnessWriteProc.failure = text.trim() }
        onExited: (code, status) => {
            if (!startFailed && (code !== 0 || status !== 0))
                root.feedback("brightness", "Could not change brightness",
                    failure || "The display rejected the brightness change.", false);
        }
        onRunningChanged: {
            if (!running) {
                if (awaitingStart) {
                    awaitingStart = false;
                    startFailed = true;
                    root.feedback("brightness", "Could not change brightness",
                        "Could not start brightnessctl. Check that it is installed and executable.", false);
                }
                Qt.callLater(root.flushBrightness);
                brightnessDebounce.restart();
            }
        }
    }

}

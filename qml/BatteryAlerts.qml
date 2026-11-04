pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Scope {
    id: root
    required property var battery
    required property var notifications
    property bool onBattery: UPower.onBattery
    readonly property string alertKey: "battery-low"
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME")
        || Quickshell.env("HOME") + "/.local/state") + "/quickshell/battery-alerts.json"
    property bool stateLoaded: false
    property bool persistenceAllowed: false
    // Lowest threshold already announced this charge cycle; 100 means none.
    property int announcedThreshold: 100
    readonly property bool batteryReady: !!battery?.ready && !!battery?.isPresent
    readonly property real percentage: battery?.percentage ?? -1
    readonly property int batteryState: battery?.state ?? UPowerDeviceState.Unknown

    onBatteryReadyChanged: settle.restart()
    onPercentageChanged: settle.restart()
    onBatteryStateChanged: settle.restart()
    onOnBatteryChanged: settle.restart()
    onStateLoadedChanged: settle.restart()
    Connections {
        target: root.notifications
        function onHistoryLoadedChanged() { settle.restart(); }
    }
    // UPower updates device properties separately. Wait for their initial
    // snapshot and brief charger transitions to settle before making a decision.
    Timer { id: settle; interval: 750; onTriggered: root.evaluate() }

    function applyLoaded(contents) {
        if (stateLoaded) return;
        let saved;
        try { saved = JSON.parse(contents); } catch (_) {}
        if (saved && saved.version === 1 && [100, 20, 10, 5].includes(saved.threshold)) {
            announcedThreshold = saved.threshold;
            persistenceAllowed = true;
        } else {
            console.warn("Battery alerts: preserving invalid or unsupported saved state; changes remain in memory");
        }
        stateLoaded = true;
    }

    function loadFailed(error) {
        if (stateLoaded) return;
        persistenceAllowed = error === FileViewError.FileNotFound;
        if (!persistenceAllowed)
            console.warn("Battery alerts: could not read saved state; preserving the original file");
        stateLoaded = true;
    }

    function saveFailed() {
        // FileView caches failed text; keep this session usable without
        // assuming an identical retry will produce a saved signal.
        persistenceAllowed = false;
        console.warn("Battery alerts: could not persist threshold; changes remain in memory");
    }

    function persist() {
        if (!stateLoaded || !persistenceAllowed) return;
        stateFile.setText(JSON.stringify({version: 1, threshold: announcedThreshold}) + "\n");
    }

    function evaluate() {
        if (!stateLoaded || !notifications.historyLoaded || !batteryReady) return;
        if (!Number.isFinite(percentage) || percentage < 0 || percentage > 1) return;
        // Unknown/pending states and onBattery's initial false value are not
        // evidence of a new cycle. An observed charging state is.
        const charging = batteryState === UPowerDeviceState.Charging
            || batteryState === UPowerDeviceState.FullyCharged;
        if (charging) {
            notifications.closeLocal(alertKey);
            if (announcedThreshold !== 100) {
                announcedThreshold = 100;
                persist();
            }
            return;
        }
        if (!onBattery) {
            notifications.closeLocal(alertKey);
            return;
        }
        if (batteryState !== UPowerDeviceState.Discharging) return;
        const percent = percentage * 100;
        // A recharge while the shell was stopped can be inferred once the
        // battery is safely above every threshold (with 5% hysteresis).
        if (percent > 25 && announcedThreshold !== 100) {
            announcedThreshold = 100;
            persist();
            notifications.closeLocal(alertKey);
        }
        const threshold = percent <= 5 ? 5 : percent <= 10 ? 10 : percent <= 20 ? 20 : 100;
        if (threshold >= announcedThreshold) return;
        if (notifications.notifyLocal(alertKey, {
            appName: "Battery", appIcon: "battery-caution-symbolic",
            summary: threshold <= 5 ? "Battery critically low" : "Low battery",
            body: Math.round(percent) + "% remaining. " + (threshold <= 5
                ? "Connect power now to avoid losing work." : "Connect power to keep working."),
            critical: threshold <= 10
        })) {
            announcedThreshold = threshold;
            persist();
        }
    }

    FileView {
        id: stateFile
        path: root.statePath
        printErrors: false
        atomicWrites: true
        onLoaded: root.applyLoaded(text())
        onLoadFailed: error => root.loadFailed(error)
        onSaveFailed: root.saveFailed()
    }
}

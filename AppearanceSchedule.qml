pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "adapters"

// Application policy. Owns manual override lifetime, not mode persistence or portal transport.
Scope {
    id: root
    property bool ready: false
    property var settings: ({mode: "manual", location: "timezone", latitude: null, longitude: null})
    property bool overrideLoaded: false
    property double overrideUntil: 0
    property string persistenceError: ""
    readonly property string error: persistenceError || provider.error
    readonly property string locationStatus: provider.locationStatus
    function refreshLocation() { provider.nextLocation = 0; provider.refresh(); }
    readonly property var nextTransition: provider.schedule ? provider.schedule.next_transition : null
    readonly property bool automatic: settings.mode === "solar"
    signal requested(bool dark)

    function saveOverride(value) {
        overrideUntil = value;
        savedOverride.setText(JSON.stringify({version: 1, until: value}) + "\n");
    }
    function manualOverride() {
        if (automatic) saveOverride(nextTransition && nextTransition > Date.now() / 1000
            ? nextTransition : Date.now() / 1000 + 86400);
    }
    function resume() {
        saveOverride(0);
        provider.lastCalculation = 0;
        provider.refresh();
    }
    function apply() {
        if (!ready || !overrideLoaded || !automatic || !provider.schedule) return;
        const now = Date.now() / 1000;
        if (overrideUntil > now) return;
        if (overrideUntil !== 0) saveOverride(0);
        requested(provider.schedule.dark);
    }
    onReadyChanged: Qt.callLater(apply)
    onOverrideLoadedChanged: Qt.callLater(apply)
    SolarProvider {
        id: provider
        enabled: root.ready && root.overrideLoaded && root.automatic
        settings: root.settings
        onUpdated: root.apply()
    }
    FileView {
        id: savedOverride
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
            + "/nullshell/appearance-override.json"
        printErrors: false
        onLoaded: {
            try {
                const value = JSON.parse(text());
                if (value.version !== 1 || !Number.isFinite(value.until) || value.until < 0) throw new Error();
                // A clock correction must not pin the appearance indefinitely.
                root.overrideUntil = Math.min(value.until, Date.now() / 1000 + 172800);
            } catch (_) { root.persistenceError = "Invalid saved appearance override"; }
            root.overrideLoaded = true;
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) root.persistenceError = "Could not read appearance override";
            root.overrideLoaded = true;
        }
        onSaved: root.persistenceError = ""
        onSaveFailed: error => root.persistenceError = "Could not save appearance override"
    }
}

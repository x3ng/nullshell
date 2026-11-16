pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// One owner for the bounded, restart-safe temporary quiet period. No replay of
// suppressed banners on resume; they remain available in the notification center.
Scope {
    id: root
    property double until: 0
    property double now: Date.now()
    property bool ready: false
    property bool writable: false
    property string error: ""
    readonly property bool active: ready && until > now
    function refresh() { now = Date.now(); }
    function pause(minutes = 60) {
        if (!ready || !Number.isInteger(minutes) || minutes < 1 || minutes > 1440) return false;
        until = Date.now() + minutes * 60000;
        save();
        return true;
    }
    function resume() {
        if (!ready) return false;
        until = 0;
        save();
        return true;
    }
    function save() {
        refresh();
        if (writable) state.setText(JSON.stringify({version: 1, until: until}) + "\n");
    }
    Timer { interval: 1000; running: root.until > root.now; repeat: true; onTriggered: root.refresh() }
    FileView {
        id: state
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
            + "/nullshell/notification-quiet.json"
        preload: true
        atomicWrites: true
        blockWrites: true
        printErrors: false
        onLoaded: {
            try {
                const value = JSON.parse(text());
                if (value.version !== 1 || !Number.isFinite(value.until) || value.until < 0
                    || value.until > Date.now() + 86400000 || Object.keys(value).some(key => !["version", "until"].includes(key)))
                    throw new Error("Invalid quiet period");
                root.until = value.until > Date.now() ? value.until : 0;
                root.writable = true;
            } catch (_) { root.error = "Invalid saved quiet period; changes remain in memory this session."; }
            root.refresh();
            root.ready = true;
        }
        onLoadFailed: error => {
            root.writable = error === FileViewError.FileNotFound;
            if (!root.writable) root.error = "Could not read the quiet period; changes remain in memory this session.";
            root.ready = true;
        }
        onSaveFailed: root.error = "Could not save the quiet period; the current choice is active only in memory."
        onSaved: root.error = ""
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "ConfigRules.js" as Rules

// Idle timing is edited as one validated snapshot. User configuration is never
// rewritten, and a failed write leaves all three running deadlines unchanged.
Scope {
    id: root
    property var configured: Rules.defaults().idle
    property var savedValues: null
    readonly property var values: savedValues ?? configured
    readonly property bool overridden: savedValues !== null
    property bool ready: false
    property bool saving: false
    property string error: ""
    property var pending: null

    function store(value): bool {
        if (!ready || saving) return false;
        try { pending = value === null ? null : Rules.idleDeadlines(value, true); }
        catch (_) {
            error = "Use whole seconds with dimming before locking and locking before display off.";
            return false;
        }
        error = "";
        saving = true;
        file.setText(JSON.stringify({version:1, idle:pending}) + "\n");
        return true;
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
            + "/nullshell/idle-policy.json"
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (data.version !== 1 || Object.keys(data).sort().join(",") !== "idle,version") throw new Error();
                root.savedValues = data.idle === null ? null : Rules.idleDeadlines(data.idle, true);
            } catch (_) { root.error = "Could not read saved idle preferences; using configuration defaults."; }
            root.ready = true;
        }
        onLoadFailed: reason => {
            if (reason !== FileViewError.FileNotFound) root.error = "Could not read saved idle preferences; using configuration defaults.";
            root.ready = true;
        }
        onSaved: {
            root.savedValues = root.pending;
            root.pending = null;
            root.saving = false;
        }
        onSaveFailed: {
            root.error = "Could not save idle preferences; deadlines were not changed.";
            root.pending = null;
            root.saving = false;
        }
    }
}

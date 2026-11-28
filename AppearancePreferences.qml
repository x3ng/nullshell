pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "ConfigRules.js" as Rules

// Explicit UI overrides only; config.json remains owned by the user/dotfiles.
Scope {
    id: root
    property var configured: Rules.defaults().appearance
    property var overrideSettings: null
    readonly property var values: overrideSettings || configured
    readonly property bool overridden: overrideSettings !== null
    property bool ready: false
    property string error: ""

    function store(value) {
        if (!ready) return false;
        try {
            const next = value === null ? null : Rules.parse(JSON.stringify({version: 1, appearance: value})).appearance;
            overrideSettings = next;
            saved.setText(JSON.stringify({version: 1, appearance: next}) + "\n");
            return true;
        } catch (_) {
            error = "Invalid appearance preference";
            return false;
        }
    }
    FileView {
        id: saved
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
            + "/nullshell/appearance-policy.json"
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const value = JSON.parse(text());
                if (value.version !== 1 || Object.keys(value).sort().join(",") !== "appearance,version") throw new Error();
                root.overrideSettings = value.appearance === null ? null
                    : Rules.parse(JSON.stringify({version: 1, appearance: value.appearance})).appearance;
            } catch (_) { root.error = "Could not read saved appearance preferences"; }
            root.ready = true;
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) root.error = "Could not read saved appearance preferences";
            root.ready = true;
        }
        onSaved: root.error = ""
        onSaveFailed: error => root.error = "Could not save appearance preferences"
    }
}

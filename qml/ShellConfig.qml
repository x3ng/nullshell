import QtQuick
import Quickshell
import Quickshell.Io
import "ConfigRules.js" as Rules

Scope {
    id: root
    property string path: (Quickshell.env("XDG_CONFIG_HOME")
        || Quickshell.env("HOME") + "/.config") + "/nullshell/config.json"
    readonly property var values: snapshot
    property var snapshot: Rules.defaults()
    property bool ready: false
    property string error: ""
    signal rejected(string reason)

    function reject(reason) {
        error = reason;
        ready = true;
        rejected(reason);
    }

    FileView {
        id: source
        path: root.path
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const next = Rules.parse(text());
                if (JSON.stringify(next) !== JSON.stringify(root.snapshot)) root.snapshot = next;
                root.error = "";
                root.ready = true;
            } catch (e) { root.reject(String(e)); }
        }
        onLoadFailed: error => {
            // Missing config on first boot is expected. On deletion retain the
            // previous snapshot; use {"version":1} for an explicit reset.
            if (error === FileViewError.FileNotFound) {
                root.error = "";
                root.ready = true;
            } else root.reject("Could not read nullshell configuration");
        }
    }
}

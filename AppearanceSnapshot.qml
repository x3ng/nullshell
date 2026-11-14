import QtQuick
import Quickshell
import Quickshell.Io
import "AppearanceRules.js" as Rules

Scope {
    id: root
    property string path: ""
    property var snapshot: null
    readonly property bool valid: snapshot !== null
    readonly property bool darkMode: !valid || snapshot.mode === "dark"
    readonly property var colors: valid ? snapshot.colors : ({})
    property string error: ""

    FileView {
        path: root.path
        blockLoading: true
        watchChanges: root.path !== ""
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.snapshot = Rules.parse(text());
                root.error = "";
            } catch (e) {
                root.error = String(e);
                console.warn("Appearance snapshot:", root.error);
            }
        }
        onLoadFailed: failure => {
            if (root.path !== "" && failure !== FileViewError.FileNotFound)
                root.error = "Could not read appearance snapshot";
            // Missing/deleted/invalid files never replace a valid in-memory theme.
        }
    }
}

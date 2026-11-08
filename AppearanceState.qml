pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Darkman owns scheduling; this file keeps the last applied mode for startup.
Scope {
    id: theme
    property bool darkMode: true
    property bool appearanceKnown: false
    readonly property bool appearanceAvailable: appearanceKnown
        && modeWatch.connected && modeControl.connected
    readonly property string appearanceError: persistenceError || desktopAppearance.error
    property string persistenceError: ""
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME")
        || Quickshell.env("HOME") + "/.local/state") + "/nullshell/appearance-mode"

    Appearance {
        id: desktopAppearance
        mode: theme.appearanceKnown ? (theme.darkMode ? "dark" : "light") : ""
    }

    function setTheme(dark) {
        if (!appearanceAvailable) return false;
        modeControl.write("set " + (dark ? "dark" : "light") + "\n");
        modeControl.flush();
        return true;
    }

    function observeMode(mode) {
        if (mode !== "dark" && mode !== "light") return;
        darkMode = mode === "dark";
        appearanceKnown = true;
        savedMode.setText(mode + "\n");
        Qt.callLater(desktopAppearance.apply);
    }

    Socket {
        id: modeWatch
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/darkman/control.sock"
        // Load the snapshot first so a late file read cannot overwrite live state.
        connected: theme.appearanceKnown
        onConnectionStateChanged: {
            if (connected) {
                write("watch\n");
                flush();
            }
        }
        parser: SplitParser {
            onRead: data => theme.observeMode(data.trim())
        }
    }

    Socket {
        id: modeControl
        path: modeWatch.path
        connected: theme.appearanceKnown
    }

    Timer {
        interval: 2000
        repeat: true
        running: theme.appearanceKnown && (!modeWatch.connected || !modeControl.connected)
        onTriggered: {
            if (!modeWatch.connected) modeWatch.connected = true;
            if (!modeControl.connected) modeControl.connected = true;
        }
    }

    FileView {
        id: savedMode
        path: theme.statePath
        printErrors: false
        onLoaded: {
            const mode = text().trim();
            theme.darkMode = mode !== "light";
            theme.appearanceKnown = true;
        }
        onLoadFailed: error => {
            theme.appearanceKnown = true;
            if (error === FileViewError.FileNotFound) savedMode.setText("dark\n");
            else theme.persistenceError = "Could not read saved appearance";
        }
        onSaved: theme.persistenceError = ""
        onSaveFailed: error => theme.persistenceError = "Could not save appearance"
    }
}

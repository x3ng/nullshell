pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// The desktop owns the effective mode. Persist it for desktop, lock and Polkit startup.
Scope {
    id: theme
    property bool darkMode: true
    property var settings: ({mode: "manual", location: "fixed", latitude: null, longitude: null})
    readonly property var nextTransition: schedule.nextTransition
    readonly property double overrideUntil: schedule.overrideUntil
    readonly property bool automatic: schedule.automatic
    property bool appearanceKnown: false
    readonly property bool appearanceAvailable: appearanceKnown
    readonly property string appearanceError: persistenceError || schedule.error || desktopAppearance.error
    property string persistenceError: ""
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME")
        || Quickshell.env("HOME") + "/.local/state") + "/nullshell/appearance-mode"

    Appearance {
        id: desktopAppearance
        mode: theme.appearanceKnown ? (theme.darkMode ? "dark" : "light") : ""
    }

    AppearanceSchedule {
        id: schedule
        ready: theme.appearanceKnown
        settings: theme.settings
        onRequested: dark => { if (theme.darkMode !== dark) theme.persistMode(dark); }
    }
    function resumeAutomatic() { schedule.resume(); }
    function persistMode(dark) {
        darkMode = dark;
        savedMode.setText((dark ? "dark" : "light") + "\n");
        Qt.callLater(desktopAppearance.apply);
    }
    function setTheme(dark) {
        if (!appearanceAvailable) return false;
        schedule.manualOverride();
        persistMode(dark);
        return true;
    }

    FileView {
        id: savedMode
        path: theme.statePath
        printErrors: false
        onLoaded: {
            const mode = text().trim();
            theme.darkMode = mode !== "light";
            theme.appearanceKnown = true;
            Qt.callLater(desktopAppearance.apply);
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

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// The desktop owns the effective mode. Persist it for desktop, lock and Polkit startup.
Scope {
    id: theme
    property bool darkMode: true
    property var settings: ({mode: "manual", location: "timezone", latitude: null, longitude: null})
    readonly property var effectiveSettings: preferences.values
    readonly property bool preferencesOverridden: preferences.overridden
    readonly property string locationStatus: schedule.locationStatus
    readonly property string selectedMode: automatic ? "auto" : darkMode ? "dark" : "light"
    readonly property var nextTransition: schedule.nextTransition
    readonly property double overrideUntil: schedule.overrideUntil
    readonly property bool automatic: schedule.automatic
    property bool appearanceKnown: false
    readonly property bool appearanceAvailable: appearanceKnown && preferences.ready
    readonly property string appearanceError: persistenceError || preferences.error || schedule.error || desktopAppearance.error
    property string persistenceError: ""
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME")
        || Quickshell.env("HOME") + "/.local/state") + "/nullshell/appearance-mode"

    Appearance {
        id: desktopAppearance
        mode: theme.appearanceKnown ? (theme.darkMode ? "dark" : "light") : ""
    }

    AppearancePreferences { id: preferences; configured: theme.settings }
    function selectMode(mode) {
        if (!appearanceAvailable || !["light", "dark", "auto"].includes(mode)) return false;
        const next = Object.assign({}, effectiveSettings, {mode: mode === "auto" ? "solar" : "manual"});
        if (mode === "auto" && next.location === "fixed" && (next.latitude === null || next.longitude === null))
            next.location = "timezone";
        if (!preferences.store(next)) return false;
        schedule.resume();
        if (mode !== "auto") persistMode(mode === "dark");
        return true;
    }
    function useIpLocation() {
        return preferences.store(Object.assign({}, effectiveSettings, {location: "ip"}));
    }
    function useTimezoneLocation() {
        return preferences.store(Object.assign({}, effectiveSettings, {location: "timezone"}));
    }
    function useFixedLocation(latitude, longitude) {
        if (typeof latitude !== "number" || !Number.isFinite(latitude) || Math.abs(latitude) > 90
            || typeof longitude !== "number" || !Number.isFinite(longitude) || Math.abs(longitude) > 180) return false;
        return preferences.store(Object.assign({}, effectiveSettings, {location: "fixed", latitude: latitude, longitude: longitude}));
    }
    function resetPreferences() {
        if (!preferences.store(null)) return false;
        schedule.resume();
        return true;
    }
    function refreshLocation() { schedule.refreshLocation(); }
    AppearanceSchedule {
        id: schedule
        ready: theme.appearanceAvailable
        settings: theme.effectiveSettings
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
        atomicWrites: true
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

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "SolarMath.js" as SolarMath

// Protocol adapter only: resolves coordinates via helper when needed and computes
// UTC solar transitions in-process without spawning a helper for arithmetic.
Scope {
    id: root
    property bool enabled: false
    property var settings: ({location: "timezone", latitude: null, longitude: null})
    property var coordinates: null
    property var schedule: null
    property string solarError: ""
    property string locationError: ""
    readonly property string error: solarError || locationError
    property double lastCalculation: 0
    property double nextLocation: 0
    property double lastClock: 0
    property bool locationPending: false
    readonly property bool fixedConfigured: Number.isFinite(settings.latitude) && Number.isFinite(settings.longitude)
    readonly property string locationStatus: !enabled ? "inactive"
        : settings.location === "fixed" ? (fixedConfigured ? "fixed" : "unset")
        : locationPending ? "locating" : coordinates ? "ready" : locationError ? "unavailable" : "locating"
    property string locationSource: "timezone"
    property int generation: 0
    property int locationGeneration: 0
    signal updated()

    function reset() {
        generation++;
        if (!enabled) {
            location.running = false;
        }
        coordinates = null;
        schedule = null;
        solarError = "";
        locationError = "";
        lastCalculation = 0;
        nextLocation = 0;
        Qt.callLater(refresh);
    }
    onEnabledChanged: reset()
    onSettingsChanged: reset()

    function refresh() {
        if (!enabled) return;
        const now = Date.now() / 1000;
        if (now < lastClock || now - lastClock > 120) {
            lastCalculation = 0;
            nextLocation = 0;
        }
        lastClock = now;
        if (settings.location === "fixed") {
            coordinates = fixedConfigured ? {latitude: settings.latitude, longitude: settings.longitude} : null;
        } else if (!locationPending && now >= nextLocation) {
            // Keep the existing schedule while refreshing or if lookup fails.
            locationSource = settings.location;
            locationPending = true;
            locationGeneration = generation;
            nextLocation = now + (locationSource === "timezone" ? 60 : 300);
            locationDeadline.restart();
            locationStartup.restart();
            location.running = true;
        }
        if (!coordinates || now - lastCalculation < 60) return;
        lastCalculation = now;
        const result = SolarMath.calculate(coordinates.latitude, coordinates.longitude, now);
        if (!result) {
            schedule = null;
            solarError = "Solar calculation unavailable; keeping current appearance";
            return;
        }
        schedule = result;
        solarError = "";
        updated();
    }

    Timer { interval: 30000; running: root.enabled; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    function locationFailed() {
        location.running = false;
        locationPending = false;
        if (!enabled || locationGeneration !== generation) {
            Qt.callLater(refresh);
            return;
        }
        locationError = coordinates ? "Location refresh failed; using the last estimate"
            : locationSource === "timezone" ? "No location for this time zone; choose fixed coordinates or IP location"
            : "IP location unavailable; keeping current appearance";
    }
    Timer { id: locationDeadline; interval: 12000; onTriggered: root.locationFailed() }
    Timer { id: locationStartup; interval: 1000; onTriggered: if (!location.running) root.locationFailed() }
    Process {
        id: location
        command: ["nullshell-helper", root.locationSource === "timezone" ? "timezone" : "location"]
        stdout: StdioCollector { id: locationOutput }
        onExited: (code, status) => {
            root.locationPending = false;
            locationDeadline.stop();
            locationStartup.stop();
            if (!root.enabled || root.locationGeneration !== root.generation) {
                Qt.callLater(root.refresh);
                return;
            }
            try {
                const value = JSON.parse(locationOutput.text);
                if (code !== 0 || status !== 0 || value.version !== 1
                    || !Number.isFinite(value.latitude) || Math.abs(value.latitude) > 90
                    || !Number.isFinite(value.longitude) || Math.abs(value.longitude) > 180) throw new Error();
                if (!root.coordinates || root.coordinates.latitude !== value.latitude
                    || root.coordinates.longitude !== value.longitude) {
                    root.generation++;
                    root.coordinates = {latitude: value.latitude, longitude: value.longitude};
                    root.lastCalculation = 0;
                }
                root.nextLocation = Date.now() / 1000 + (root.locationSource === "timezone" ? 60 : 1800);
                root.locationError = "";
                Qt.callLater(root.refresh);
            } catch (_) {
                root.locationFailed();
            }
        }
    }
}

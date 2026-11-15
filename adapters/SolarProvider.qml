pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Protocol adapter only: no theme decisions, user preferences or persistence.
Scope {
    id: root
    property bool enabled: false
    property var settings: ({location: "fixed", latitude: null, longitude: null})
    property var coordinates: null
    property var schedule: null
    property string error: ""
    property double lastCalculation: 0
    property double nextLocation: 0
    property double lastClock: 0
    property bool solarPending: false
    property bool locationPending: false
    property string solarRequest: ""
    property int generation: 0
    property int solarGeneration: 0
    property int locationGeneration: 0
    signal updated()

    function reset() {
        generation++;
        // In-flight results carry their generation and are discarded. A process
        // must finish before reusing its collector/request state.
        if (!enabled) {
            solar.running = false;
            location.running = false;
        }
        coordinates = null;
        schedule = null;
        error = "";
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
            coordinates = {latitude: settings.latitude, longitude: settings.longitude};
        } else if (!locationPending && now >= nextLocation) {
            // A refresh invalidates older calculations; a late solar reply must
            // not override a failed or still-pending location request.
            generation++;
            coordinates = null;
            schedule = null;
            locationPending = true;
            locationGeneration = generation;
            nextLocation = now + 300;
            locationDeadline.restart();
            locationStartup.restart();
            location.running = true;
        }
        if (!coordinates || solarPending || now - lastCalculation < 60) return;
        solarPending = true;
        solarGeneration = generation;
        solarRequest = JSON.stringify({version: 1, latitude: coordinates.latitude,
            longitude: coordinates.longitude, timestamp: now}) + "\n";
        lastCalculation = now;
        solarDeadline.restart();
        solar.running = true;
    }
    Timer { interval: 30000; running: root.enabled; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
    Timer {
        id: solarDeadline
        interval: 5000
        onTriggered: {
            solar.running = false;
            root.solarPending = false;
            if (!root.enabled || root.solarGeneration !== root.generation) {
                Qt.callLater(root.refresh);
                return;
            }
            root.schedule = null;
            root.error = "Solar helper unavailable; keeping current appearance";
        }
    }
    function locationFailed() {
        location.running = false;
        locationPending = false;
        if (!enabled || locationGeneration !== generation) {
            Qt.callLater(refresh);
            return;
        }
        coordinates = null;
        schedule = null;
        error = "Location unavailable; keeping current appearance";
    }
    Timer { id: locationDeadline; interval: 35000; onTriggered: root.locationFailed() }
    Timer { id: locationStartup; interval: 1000; onTriggered: if (!location.running) root.locationFailed() }
    Process {
        id: location
        command: ["nullshell-helper", "location"]
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
                root.coordinates = {latitude: value.latitude, longitude: value.longitude};
                root.nextLocation = Date.now() / 1000 + 1800;
                root.lastCalculation = 0;
                root.error = "";
                Qt.callLater(root.refresh);
            } catch (_) {
                root.coordinates = null;
                root.schedule = null;
                root.error = "Location unavailable; keeping current appearance";
            }
        }
    }
    Process {
        id: solar
        command: ["nullshell-helper", "solar"]
        stdinEnabled: true
        onStarted: {
            write(root.solarRequest);
            stdinEnabled = false;
        }
        stdout: StdioCollector { id: solarOutput }
        onExited: (code, status) => {
            root.solarPending = false;
            solarDeadline.stop();
            stdinEnabled = true;
            if (!root.enabled || root.solarGeneration !== root.generation) {
                Qt.callLater(root.refresh);
                return;
            }
            try {
                const value = JSON.parse(solarOutput.text);
                if (code !== 0 || status !== 0 || value.version !== 1 || typeof value.dark !== "boolean"
                    || !(value.next_transition === null || Number.isFinite(value.next_transition))) throw new Error();
                root.schedule = value;
                root.error = "";
                root.updated();
            } catch (_) {
                root.schedule = null;
                root.error = "Solar calculation unavailable; keeping current appearance";
            }
        }
    }
}

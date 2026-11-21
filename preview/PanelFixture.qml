import Quickshell.Services.Mpris
import QtQuick
import Quickshell
import "../SearchQuery.js" as SearchQuery

// Deliberately no native services, processes, FileViews or persistent state.
// Every command below only changes these synthetic, in-memory objects.
Scope {
    id: fixture
    property string scenario: "normal"
    property string lastAction: ""
    property bool quietReady: true
    property bool doNotDisturb: false
    property double quietUntil: 0
    property string quietError: ""
    function pause(minutes = 60) { doNotDisturb = true; quietUntil = Date.now() + minutes * 60000; return true; }
    function resume() { doNotDisturb = false; quietUntil = 0; return true; }
    property QtObject session: QtObject {
        property bool busy: false
        property string error: ""
        property bool supported: true
        signal accepted(string action)
        function refresh() {}
        function available(action) { return supported && !busy; }
        function execute(action) {
            if (!available(action)) return false;
            fixture.lastAction = "session:" + action;
            return true;
        }
    }
    property string query: ""
    signal navigateRequested(string section)
    signal operationFinished(bool success, string operation, string target, int requestId, string message)
    property var controls: fixture
    property bool darkMode: true
    property bool appearanceAvailable: true
    property bool appearanceKnown: true
    property bool automatic: false
    property bool preferencesOverridden: false
    property string appearanceError: ""
    property string locationStatus: "inactive"
    property double overrideUntil: 0
    property var nextTransition: 1794736800
    property var effectiveSettings: ({mode: "manual", location: "ip", latitude: null, longitude: null})
    readonly property string selectedMode: automatic ? "auto" : darkMode ? "dark" : "light"
    function selectMode(mode) {
        automatic = mode === "auto";
        if (!automatic) darkMode = mode === "dark";
        preferencesOverridden = true;
        locationStatus = automatic ? "ready" : "inactive";
        overrideUntil = 0;
        lastAction = "appearance:" + mode;
        return true;
    }
    function useIpLocation() {
        effectiveSettings = {mode: "solar", location: "ip", latitude: null, longitude: null};
        preferencesOverridden = true;
        locationStatus = "ready";
        return true;
    }
    function useTimezoneLocation() {
        effectiveSettings = {mode: "solar", location: "timezone", latitude: null, longitude: null};
        preferencesOverridden = true;
        locationStatus = "ready";
        return true;
    }
    function useFixedLocation(latitude, longitude) {
        if (!Number.isFinite(latitude) || Math.abs(latitude) > 90 || !Number.isFinite(longitude) || Math.abs(longitude) > 180) return false;
        effectiveSettings = {mode: "solar", location: "fixed", latitude: latitude, longitude: longitude};
        preferencesOverridden = true;
        locationStatus = "fixed";
        return true;
    }
    function resumeAutomatic() { overrideUntil = 0; lastAction = "appearance:resume"; }
    function refreshLocation() { appearanceError = ""; locationStatus = "ready"; }
    function resetPreferences() {
        automatic = false; preferencesOverridden = false; appearanceError = "";
        locationStatus = "inactive"; overrideUntil = 0;
        effectiveSettings = {mode: "manual", location: "ip", latitude: null, longitude: null};
    }
    property QtObject shortcuts: QtObject {
        readonly property string status: ""
        readonly property var rows: [
            {chord: "Super + Return", description: "Open terminal", dispatcher: "exec"},
            {chord: "Super + Shift + S", description: "Capture a region", dispatcher: "exec"}
        ]
        function refresh() {}
    }
    function keepAwakeFor(minutes) {
        keepAwakeUntil = minutes ? Date.now() + minutes * 60000 : 0;
        keepAwake = keepAwakeRequested || keepAwakeUntil > 0;
        return true;
    }
    property bool keepAwakeReady: true
    property double keepAwakeUntil: 0
    property bool keepAwakeRequested: true
    property bool keepAwake: true
    property var trayItems: scenario === "empty" ? [] : Array.from({length: scenario === "crowded" ? 6 : 1}, () => tray)
    QtObject {
        id: tray
        property string title: "Preview tray item"
        property string tooltipTitle: title
        property string tooltipDescription: "Synthetic tray; no real application"
        property string icon: ""
        property bool onlyMenu: false
        property var menu: null
        function activate() { fixture.lastAction = "tray activated"; }
        function secondaryActivate() { fixture.lastAction = "tray secondary activated"; }
    }
    property real brightness: 0.7
    property var terminalCommand: ["preview-only"]
    property var sink: output
    property var source: input
    property var audioOutputs: [output]
    property bool mixerVisible: false
    readonly property var playbackStreams: mixerVisible && scenario !== "empty" ? [previewStream] : []
    QtObject {
        id: previewStream
        readonly property int id: 17
        readonly property var properties: ({"application.name": "Preview browser", "media.name": "Video playback"})
        property QtObject audio: QtObject { property real volume: 0.62; property bool muted: false }
    }
    property var audioInputs: [input]
    QtObject { id: output; property string description: "Preview speakers"; property var audio: outputAudio }
    QtObject { id: outputAudio; property real volume: 0.45; property bool muted: false }
    QtObject { id: input; property string description: "Preview microphone"; property var audio: inputAudio }
    QtObject { id: inputAudio; property real volume: 0.6; property bool muted: false }
    property var battery: scenario === "empty" ? null : ({isPresent: true, percentage: 0.76, state: 2})
    function batteryDetail(battery) { return "On battery"; }
    function setVolume(value) { outputAudio.volume = value; }
    function setBrightness(value) { brightness = value; }
    function selectAudioDevice(device, isInput) { lastAction = "select audio"; }

    readonly property var players: scenario === "crowded" ? [media, broadcast] : scenario === "media" ? [media] : []
    readonly property var player: players.find(p => p.isPlaying) ?? players[0] ?? null
    QtObject {
        id: broadcast
        property string identity: "Radio"
        property string trackTitle: "Live broadcast"
        property string trackArtist: ""
        property bool positionSupported: false
        property bool lengthSupported: false
        property bool canSeek: false
        property bool isPlaying: false
        property bool canTogglePlaying: true
        property bool canGoNext: false
        property bool canGoPrevious: false
        property real position: 0
        function togglePlaying() { isPlaying = !isPlaying; }
    }
    QtObject {
        id: media
        property bool canControl: true
        property bool shuffleSupported: true
        property bool loopSupported: true
        property bool shuffle: false
        property int loopState: MprisLoopState.None
        property real position: 45
        property real length: 180
        property bool positionSupported: true
        property bool lengthSupported: true
        property bool canSeek: true
        property string uniqueId: "fixture-track"
        property string trackTitle: "A very long track title to check truncation without changing the panel width"
        property string trackArtist: "Preview artist"
        property string identity: "Preview player"
        property string trackArtUrl: ""
        property bool isPlaying: true
        property bool canGoPrevious: true
        property bool canGoNext: true
        property bool canTogglePlaying: true
        function previous() { fixture.lastAction = "previous track"; }
        function next() { fixture.lastAction = "next track"; }
        function togglePlaying() { isPlaying = !isPlaying; }
    }

    property bool wifiAvailable: true
    property bool wifiEnabled: true
    property bool bluetoothAvailable: true
    property bool bluetoothEnabled: true
    property string wifiConnection: wifiNetworks.find(n => n.connected)?.name || "Not connected"
    property var wifiNetworks: scenario === "empty" ? [] : [
        {name: scenario === "crowded" ? "A deliberately long wireless network name" : "Studio Wi-Fi", connected: true, signalStrength: 0.82, known: true, device: {name: "wlan-test"}},
        {name: "Guest network", connected: false, signalStrength: 0.53, known: false, device: {name: "wlan-test"}},
        {name: "Enterprise network", connected: false, signalStrength: 0.65, known: false, unsupported: true, device: {name: "wlan-test"}}
    ]
    property var wifiNearbyNetworks: wifiNetworks
    property bool wifiBusy: false
    property string wifiError: ""
    property string bluetoothError: ""
    property bool bluetoothBusy: false
    property bool bluetoothScanRequested: false
    property var pairingDevice: null
    property string pairingPrompt: ""
    property string pairingCode: ""
    property var bluetoothDevices: scenario === "empty" ? [] : [
        {name: scenario === "crowded" ? "A deliberately long headphone name" : "Headphones", address: "preview-headphones", connected: true, paired: true, batteryAvailable: true, battery: 0.72},
        {name: "Mouse", address: "preview-mouse", connected: scenario === "crowded", paired: true, batteryAvailable: false}
    ]
    property var bluetoothConnected: bluetoothDevices.filter(d => d.connected)
    function wifiKey(device) { return device.name; }
    function bluetoothKey(device) { return device.address; }
    function wifiNetworkLabel(device) { return (device.connected ? "Connected" : "Available") + " · " + Math.round(device.signalStrength * 100) + "%"; }
    function bluetoothDeviceLabel(device) { return device.connected ? "Connected" : "Paired"; }
    function bluetoothDeviceBusy(device) { return false; }
    function wifiUsesPassword(device) { return false; }
    function wifiCanJoin(device) { return !device.unsupported; }
    function wifiPasswordValid(device, password) { return true; }
    function cancelBluetoothPairing() { pairingDevice = null; }
    function answerBluetoothPairing(answer) { lastAction = "pairing response"; }
    function stopBluetoothScan() { bluetoothScanRequested = false; }
    function clearWifiError() { wifiError = ""; }
    function clearBluetoothError() { bluetoothError = ""; }
    function toggleBluetoothScan() { bluetoothScanRequested = !bluetoothScanRequested; }
    function connectWifi(device, password) { lastAction = "connect wifi"; return true; }
    function disconnectWifi(device) { lastAction = "disconnect wifi"; }
    function forgetWifi(device) { lastAction = "forget wifi"; return true; }
    function toggleBluetoothDevice(device) { lastAction = "toggle bluetooth device"; return true; }
    function pairBluetooth(device) { lastAction = "pair bluetooth"; return true; }
    function forgetBluetooth(device) { lastAction = "forget bluetooth"; return true; }

    property bool available: true
    property bool busy: false
    property string error: ""
    property int lastRequestId: 0
    property string focusedWorkspaceAddress: "preview-1"
    property var workspaces: scenario === "empty" ? [] : Array.from({length: scenario === "crowded" ? 9 : 3}, (_, i) => ({
        address: "preview-" + (i + 1), name: String(i + 1), active: i === 0, exists: true, layout: "dwindle", monitor: "Preview"
    })).concat([{address: "special:scratchpad", name: "scratchpad", special: true,
        active: false, exists: true, layout: "dwindle", monitor: "Preview"}])
    property var workspaceTargets: workspaces
    property int titleRevision: 0
    property var windows: scenario === "empty" ? [] : workspaces.reduce((all, w, i) => all.concat(
        Array.from({length: scenario === "crowded" ? 3 : 1}, (_, j) => ({
            address: "window-" + i + "-" + j, workspaceAddress: w.address, appId: i % 2 ? "browser" : "terminal",
            title: (scenario === "crowded" ? "A very long terminal title that keeps changing " : "Preview window ") + (i + titleRevision) + " / " + j,
            focused: i === 0 && j === 0, floating: false, fullscreen: false
        }))), [])
    function focusWorkspace(address) { focusedWorkspaceAddress = address; lastAction = "focus " + address; return false; }
    function focusWindow(address) { lastAction = "focus " + address; return false; }
    function moveWindow(address, workspace) { lastAction = "move " + address; return false; }
    function closeWindow(address) { lastAction = "close " + address; return false; }
    function toggleFloat(address) { lastAction = "float " + address; return false; }
    function toggleFullscreen(address) { lastAction = "fullscreen " + address; return false; }
    function setLayout(address, layout) { lastAction = "layout " + layout; return false; }

    property var current: scenario === "empty" ? [] : [{
        recordKey: "download", id: 1, appName: "Preview", summary: "Download completed — ready to review",
        body: "Synthetic notification. No application is contacted.", time: Date.now(), urgency: 1
    }]
    property var history: scenario === "empty" ? [] : [...current, {
        recordKey: "message", appName: "Messenger", summary: "Incoming message",
        body: "Preview conversation", time: Date.now(), urgency: 1
    }]
    function entryActions(entry) { return []; }
    function activationLabel(entry) { return ""; }
    function activateEntry(entry) { lastAction = "notification"; return false; }
    function invokeEntryAction(entry, action) { return false; }
    function clearCurrent() { current = []; }
    function clearHistory() { history = []; }
    function removeCurrent(index) { current = current.filter((_, i) => i !== index); }
    function removeHistory(index) { history = history.filter((_, i) => i !== index); }

    readonly property string scope: query.trim().startsWith(">") ? "ACTION" : "ALL"
    readonly property string scopeLabel: scope === "ACTION"
        ? (SearchQuery.commandFilter(query) === "panel" ? "Panels" : SearchQuery.commandFilter(query) === "operation" ? "Actions" : "Commands") : "Preview results"
    readonly property var commandRows: [
        {key: "session", title: "Power and session", actionType: "panel", detail: "Lock, sleep or leave the session", icon: "power", enabled: true},
        {key: "appearance", title: "Appearance settings", actionType: "panel", detail: "Light, dark and automatic", icon: "brightness", enabled: true},
        {key: "wifi", title: "Wi-Fi settings", actionType: "panel", detail: "Choose a network", icon: "wifi", enabled: true},
        {key: "dark", title: "Use dark appearance", actionType: "operation", detail: "Switch desktop and applications", icon: "moon", enabled: true},
        {key: "power:balanced", title: "Use power profile: balanced", actionType: "operation", detail: "Change performance and energy use", icon: "battery", enabled: true},
        {key: "keyboard", title: "Show screen keyboard", actionType: "operation", detail: "No keyboard available", icon: "keyboard", enabled: false}
    ]
    property var results: scope === "ACTION" ? commandRows
        .filter(row => (SearchQuery.commandFilter(query) === "all" || row.actionType === SearchQuery.commandFilter(query))
            && (row.title + " " + row.detail).toLowerCase().includes(SearchQuery.commandText(query).toLowerCase()))
        .map(row => Object.assign({}, row, {kind: "ACTION", entry: null}))
        : !query.trim() || scenario === "empty" ? [] : windows.map((w, i) => ({
        key: w.address, kind: "WINDOW", title: w.title, detail: "Workspace " + (i + 1), enabled: true, entry: null
    }))
    function desktopEntryFor(window) { return null; }
    function desktopIconSource(entry) { return ""; }
    function activateResult(result, forceTerminal) { lastAction = "activate " + result.key; return {accepted: true, closePanel: false}; }
    function execute(action) {
        lastAction = action;
        if (["overview", "desktop", "wifi", "bluetooth", "audio", "media", "notifications", "appearance", "session"].includes(action)) navigateRequested(action);
        else if (action === "auto") selectMode("auto");
        else if (action === "appearance-resume") resumeAutomatic();
        else if (action === "keep-awake") keepAwake = !keepAwake;
        else if (action === "notifications-pause") pause();
        else if (action === "notifications-resume") resume();
        else if (action === "light" || action === "dark") {
            darkMode = action === "dark";
            if (automatic) overrideUntil = 1794736800;
        }
        else if (action === "wifi-toggle") wifiEnabled = !wifiEnabled;
        else if (action === "bluetooth-toggle") bluetoothEnabled = !bluetoothEnabled;
        else if (action === "output-mute") outputAudio.muted = !outputAudio.muted;
    }
}

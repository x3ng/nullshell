import QtQuick
import Quickshell

// Deliberately no native services, processes, FileViews or persistent state.
// Every command below only changes these synthetic, in-memory objects.
Scope {
    id: fixture
    property string scenario: "normal"
    property string lastAction: ""
    property string query: ""
    signal navigateRequested(string section)
    signal operationFinished(bool success, string operation, string target, int requestId, string message)
    property var controls: fixture
    property bool darkMode: true
    property bool appearanceAvailable: true
    property bool keepAwake: true
    property var trayItems: scenario === "empty" ? [] : [tray]
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
    function openNetworkEditor() { lastAction = "network editor"; }

    property var player: scenario === "media" || scenario === "crowded" ? media : null
    QtObject {
        id: media
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
        {name: "Guest network", connected: false, signalStrength: 0.53, known: false, device: {name: "wlan-test"}}
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
    function wifiCanJoin(device) { return true; }
    function wifiPasswordValid(device, password) { return true; }
    function cancelBluetoothPairing() { pairingDevice = null; }
    function answerBluetoothPairing(answer) { lastAction = "pairing response"; }
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
    }))
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
        id: 1, appName: "Preview", summary: "Download completed — ready to review",
        body: "Synthetic notification. No application is contacted.", time: Date.now(), urgency: 1
    }]
    property var history: current
    function entryActions(entry) { return []; }
    function activationLabel(entry) { return ""; }
    function activateEntry(entry) { lastAction = "notification"; return false; }
    function invokeEntryAction(entry, action) { return false; }
    function clearCurrent() { current = []; }
    function clearHistory() { history = []; }
    function removeCurrent(index) { current = current.filter((_, i) => i !== index); }
    function removeHistory(index) { history = history.filter((_, i) => i !== index); }

    property string scope: "ALL"
    property string scopeLabel: "Preview results"
    property var results: !query.trim() || scenario === "empty" ? [] : windows.map((w, i) => ({
        key: w.address, kind: "WINDOW", title: w.title, detail: "Workspace " + (i + 1), enabled: true, entry: null
    }))
    function desktopEntryFor(window) { return null; }
    function desktopIconSource(entry) { return ""; }
    function activateResult(result, forceTerminal) { lastAction = "activate " + result.key; return {accepted: true, closePanel: false}; }
    function execute(action) {
        lastAction = action;
        if (["overview", "desktop", "wifi", "bluetooth", "audio", "notifications"].includes(action)) navigateRequested(action);
        else if (action === "keep-awake") keepAwake = !keepAwake;
        else if (action === "light" || action === "dark") darkMode = action === "dark";
        else if (action === "wifi-toggle") wifiEnabled = !wifiEnabled;
        else if (action === "bluetooth-toggle") bluetoothEnabled = !bluetoothEnabled;
        else if (action === "output-mute") outputAudio.muted = !outputAudio.muted;
    }
}

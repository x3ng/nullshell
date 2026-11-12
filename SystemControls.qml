pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import "components/ConnectionFeedback.js" as ConnectionFeedback
import "adapters"

// Native service objects own device state and ordinary actions. Pairing alone
// uses an on-demand BlueZ agent bridge because this version has no Agent1 API.
Scope {
    id: root
    property bool active: false
    // Discovery is needed only in Wi-Fi details; connected state stays subscribed.
    property bool wifiDiscoveryActive: false
    property string error: ""
    property string wifiError: ""
    property string bluetoothError: ""
    property bool bluetoothScanRequested: false
    readonly property var pairingDevice: pairing.device
    readonly property string pairingPrompt: pairing.prompt
    readonly property string pairingCode: pairing.code
    signal feedback(string key, string summary, string body, bool critical)
    property var connectionTracker: ConnectionFeedback.create()

    function wifiKey(network) {
        return network?.device ? "wifi:" + network.device.name + ":" + network.name + ":" + (network.security ?? "") : "";
    }
    function bluetoothKey(device) { return device ? "bluetooth:" + device.address : ""; }

    function observeConnections() {
        const rows = wifiEnabled ? wifiNetworks.filter(network => !!network?.device).map(network => ({
            key: wifiKey(network), name: network.name, kind: "wifi", device: network.device.name, connected: network.connected,
            connecting: network.state === ConnectionState.Connecting
        })) : [];
        if (bluetoothEnabled) {
            for (const device of bluetoothDevices) rows.push({
                key: bluetoothKey(device), name: device.name || device.address, kind: "bluetooth",
                connected: device.state === BluetoothDeviceState.Connected,
                connecting: device.state === BluetoothDeviceState.Connecting
            });
        }
        for (const event of ConnectionFeedback.observe(connectionTracker, rows, Date.now())) {
            const kind = event.kind === "wifi" ? "Wi-Fi" : "Bluetooth";
            const summary = kind + (event.result === "connected" ? " connected"
                : event.result === "failed" ? " connection failed" : " disconnected");
            const body = event.name + (event.reason ? ": " + event.reason : "");
            if (event.result === "failed") {
                error = body;
                if (event.kind === "wifi") wifiError = body;
                else bluetoothError = body;
            }
            feedback(event.key, summary, body, false);
        }
        connectionDeadline.running = connectionTracker.pending;
    }
    function scheduleConnectionObservation() { Qt.callLater(observeConnections); }
    onWifiNetworksChanged: scheduleConnectionObservation()
    onBluetoothDevicesChanged: {
        if (pairingDevice && !bluetoothDevices.includes(pairingDevice)) cancelBluetoothPairing();
        scheduleConnectionObservation();
    }
    onWifiEnabledChanged: {
        if (!wifiEnabled) ConnectionFeedback.silence(connectionTracker, "wifi:");
        scheduleConnectionObservation();
    }
    onBluetoothEnabledChanged: {
        if (!bluetoothEnabled) {
            ConnectionFeedback.silence(connectionTracker, "bluetooth:");
            bluetoothScanRequested = false;
            cancelBluetoothPairing();
        }
        scheduleConnectionObservation();
    }
    Component.onCompleted: {
        scheduleConnectionObservation();
        refreshPowerAvailability();
    }
    onActiveChanged: {
        if (active) refreshPowerAvailability();
        else { bluetoothScanRequested = false; cancelBluetoothPairing(); }
    }

    // Quickshell 0.3.2 exposes no PowerProfiles availability/ready property.
    // Probe its actual D-Bus endpoint at startup and when opening the panel.
    property bool powerServiceAvailable: false
    function refreshPowerAvailability() {
        if (powerProbe.running) return;
        powerProbe.output = "";
        powerProbe.hasStarted = false;
        powerProbe.running = true;
        powerStartupCheck.restart();
    }
    Process {
        id: powerProbe
        property bool hasStarted: false
        property string output: ""
        command: ["busctl", "--system", "--timeout=2", "--json=short", "get-property",
            "net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "net.hadess.PowerProfiles", "ActiveProfile"]
        stdout: StdioCollector { onStreamFinished: powerProbe.output = text }
        onStarted: hasStarted = true
        onExited: (code, status) => {
            let available = false;
            if (code === 0 && status === 0) {
                try {
                    const result = JSON.parse(output);
                    available = result.type === "s" && ["power-saver", "balanced", "performance"].includes(result.data);
                } catch (_) {}
            }
            root.powerServiceAvailable = available;
        }
    }
    Timer {
        id: powerStartupCheck
        interval: 1000
        onTriggered: {
            if (!powerProbe.hasStarted && !powerProbe.running) root.powerServiceAvailable = false;
        }
    }
    Timer {
        id: connectionDeadline
        interval: 1000
        repeat: true
        onTriggered: root.observeConnections()
    }
    readonly property var wifiDevices: Networking.devices.values.filter(device => device.type === DeviceType.Wifi)
    readonly property var wifiNetworks: wifiDevices.reduce((networks, device) => networks.concat(device.networks.values), [])
    readonly property var wifiNearbyNetworks: wifiNetworks.filter(network => network.name !== "")
        .sort((a, b) => Number(b.connected) - Number(a.connected) || Number(b.known) - Number(a.known)
            || a.name.localeCompare(b.name) || a.device.name.localeCompare(b.device.name) || a.security - b.security)
    readonly property bool wifiAvailable: wifiDevices.length > 0
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property string wifiConnection: wifiNetworks.find(network => network.connected)?.name ?? "Not connected"
    readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
    readonly property bool bluetoothAvailable: bluetoothAdapter !== null
    readonly property bool bluetoothEnabled: bluetoothAdapter?.enabled ?? false
    readonly property var bluetoothDevices: (bluetoothAdapter?.devices.values ?? []).slice()
        .sort((a, b) => Number(b.connected) - Number(a.connected)
            || Number(b.paired) - Number(a.paired) || (a.name || a.address).localeCompare(b.name || b.address))
    readonly property var bluetoothConnected: bluetoothDevices.filter(device => device.connected).map(device => device.address)
    readonly property var powerProfiles: powerAvailable
        ? ["power-saver", "balanced"].concat(PowerProfiles.hasPerformanceProfile ? ["performance"] : []) : []
    readonly property bool powerAvailable: powerServiceAvailable
    readonly property string powerProfile: powerAvailable ? profileSlug(PowerProfiles.profile) : ""
    readonly property bool wifiBusy: wifiNetworks.some(network => network.stateChanging)
    readonly property bool bluetoothBusy: bluetoothDevices.some(device => device.state === BluetoothDeviceState.Connecting
            || device.state === BluetoothDeviceState.Disconnecting)
        || bluetoothAdapter?.state === BluetoothAdapterState.Enabling
        || bluetoothAdapter?.state === BluetoothAdapterState.Disabling

    readonly property bool busy: wifiBusy || bluetoothBusy

    function bluetoothDeviceBusy(device) {
        return device === pairingDevice || device.pairing || device.state === BluetoothDeviceState.Connecting
            || device.state === BluetoothDeviceState.Disconnecting;
    }
    function bluetoothDeviceLabel(device) {
        if (device === pairingDevice || device.pairing) return "Pairing…";
        if (device.state === BluetoothDeviceState.Connecting) return "Connecting…";
        if (device.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…";
        const state = device.connected ? "Connected" : device.paired ? "Paired" : "Available to pair";
        return state + (device.batteryAvailable ? " · " + Math.round(device.battery * 100) + "%" : "");
    }

    function wifiSecurityLabel(network) { return WifiSecurityType.toString(network.security); }
    function wifiUsesPassword(network) {
        return [WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae].includes(network.security);
    }
    function wifiCanJoin(network) {
        return network.known || wifiUsesPassword(network)
            || network.security === WifiSecurityType.Open || network.security === WifiSecurityType.Owe;
    }
    function wifiPasswordValid(network, password) {
        if (network.security === WifiSecurityType.Sae) return password.length > 0 && password.length <= 63;
        return (password.length >= 8 && password.length <= 63) || /^[0-9a-fA-F]{64}$/.test(password);
    }
    function wifiNetworkLabel(network) {
        const state = network.stateChanging ? ConnectionState.toString(network.state)
            : network.connected ? "Connected" : network.known ? "Saved" : "New network";
        return state + " · " + wifiSecurityLabel(network) + " · " + Math.round(network.signalStrength * 100) + "%";
    }

    Binding {
        target: root.bluetoothAdapter
        property: "discovering"
        when: root.bluetoothAdapter !== null
        value: root.active && root.bluetoothEnabled && root.bluetoothScanRequested
        restoreMode: Binding.RestoreNone
    }
    onBluetoothScanRequestedChanged: { if (bluetoothScanRequested) scanDeadline.restart(); else scanDeadline.stop(); }
    Timer { id: scanDeadline; interval: 20000; onTriggered: root.bluetoothScanRequested = false }
    function toggleBluetoothScan() {
        if (!bluetoothEnabled) return false;
        bluetoothScanRequested = !bluetoothScanRequested;
        return true;
    }

    BluetoothPairing {
        id: pairing
        onFinished: (device, success, message) => {
            if (!success) {
                root.bluetoothError = message;
                root.feedback(root.bluetoothKey(device), "Bluetooth pairing failed", message, false);
                return;
            }
            // Native services remain the source of truth. A vanished device or
            // disabled radio must not receive follow-up trust/connect actions.
            if (!root.bluetoothEnabled || !root.bluetoothDevices.includes(device)) return;
            device.trusted = true;
            root.observeConnections();
            ConnectionFeedback.request(root.connectionTracker, root.bluetoothKey(device), Date.now());
            device.connected = true;
            root.scheduleConnectionObservation();
        }
    }
    function pairBluetooth(device) {
        if (!bluetoothEnabled || !device || device.paired || !bluetoothDevices.includes(device)) return false;
        if (!pairing.start(device)) return false;
        bluetoothError = "";
        stopBluetoothScan();
        return true;
    }
    function answerBluetoothPairing(answer) { return pairing.answer(answer); }
    function cancelBluetoothPairing() { return pairing.cancel(); }
    function stopBluetoothScan() { bluetoothScanRequested = false; }
    function clearWifiError() { wifiError = ""; }
    function clearBluetoothError() { bluetoothError = ""; }

    function forgetBluetooth(device) {
        if (!bluetoothEnabled || bluetoothDeviceBusy(device) || !bluetoothDevices.includes(device) || !device.paired) return false;
        bluetoothError = "";
        ConnectionFeedback.silence(connectionTracker, bluetoothKey(device), true);
        device.forget();
        scheduleConnectionObservation();
        return true;
    }

    Instantiator {
        model: root.wifiDevices
        delegate: Binding {
            required property var modelData
            target: modelData
            property: "scannerEnabled"
            value: root.active && root.wifiDiscoveryActive
            restoreMode: Binding.RestoreNone
        }
    }
    Instantiator {
        model: root.wifiNetworks
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectedChanged() { root.scheduleConnectionObservation(); }
            function onStateChanged() { root.scheduleConnectionObservation(); }
            function onRequestDisconnect() {
                if (!modelData?.device) return;
                ConnectionFeedback.silence(root.connectionTracker, root.wifiKey(modelData), true);
                root.scheduleConnectionObservation();
            }
            function onConnectionFailed(reason) {
                if (!modelData?.device) return;
                root.error = modelData.name + ": " + ConnectionFailReason.toString(reason);
                root.wifiError = root.error;
                ConnectionFeedback.failure(root.connectionTracker, root.wifiKey(modelData), ConnectionFailReason.toString(reason));
                root.scheduleConnectionObservation();
            }
        }
    }
    Instantiator {
        model: root.bluetoothDevices
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectedChanged() { root.scheduleConnectionObservation(); }
            function onStateChanged() { root.scheduleConnectionObservation(); }
        }
    }
    function toggleWifi() {
        if (!wifiAvailable || wifiBusy) return false;
        error = "";
        wifiError = "";
        if (wifiEnabled) ConnectionFeedback.silence(connectionTracker, "wifi:");
        Networking.wifiEnabled = !Networking.wifiEnabled;
        scheduleConnectionObservation();
        return true;
    }
    function toggleBluetooth() {
        if (!bluetoothAdapter || bluetoothBusy) return false;
        error = "";
        bluetoothError = "";
        if (bluetoothEnabled) ConnectionFeedback.silence(connectionTracker, "bluetooth:");
        bluetoothAdapter.enabled = !bluetoothAdapter.enabled;
        scheduleConnectionObservation();
        return true;
    }
    function connectWifi(network, password = "") {
        if (!wifiEnabled || wifiBusy || !wifiNearbyNetworks.includes(network) || network.connected) return false;
        if (!wifiCanJoin(network)) { wifiError = "This network needs advanced authentication. Open network settings below."; return false; }
        if ((!network.known || password !== "") && wifiUsesPassword(network) && !wifiPasswordValid(network, password)) {
            wifiError = "Enter a valid Wi-Fi password.";
            return false;
        }
        error = "";
        wifiError = "";
        observeConnections();
        // The tracker scopes switch suppression to this network's device.
        ConnectionFeedback.request(connectionTracker, wifiKey(network), Date.now());
        if (password !== "") network.connectWithPsk(password);
        else network.connect();
        scheduleConnectionObservation();
        return true;
    }
    function disconnectWifi(network) {
        if (!wifiEnabled || wifiBusy || !wifiNearbyNetworks.includes(network) || !network.connected) return false;
        wifiError = "";
        ConnectionFeedback.silence(connectionTracker, wifiKey(network), true);
        network.disconnect();
        scheduleConnectionObservation();
        return true;
    }
    function forgetWifi(network) {
        if (!wifiEnabled || wifiBusy || !wifiNearbyNetworks.includes(network) || !network.known) return false;
        wifiError = "";
        ConnectionFeedback.silence(connectionTracker, wifiKey(network), true);
        network.forget();
        scheduleConnectionObservation();
        return true;
    }
    function toggleBluetoothDevice(device) {
        if (!bluetoothEnabled || !device.paired || bluetoothDeviceBusy(device) || !bluetoothDevices.includes(device)) return false;
        error = "";
        bluetoothError = "";
        observeConnections();
        if (device.connected) ConnectionFeedback.silence(connectionTracker, bluetoothKey(device), true);
        else ConnectionFeedback.request(connectionTracker, bluetoothKey(device), Date.now());
        device.connected = !device.connected;
        scheduleConnectionObservation();
        return true;
    }
    function profileSlug(profile) {
        if (profile === PowerProfile.PowerSaver) return "power-saver";
        if (profile === PowerProfile.Performance) return "performance";
        return "balanced";
    }
    function setPowerProfile(profile) {
        if (!powerAvailable || !powerProfiles.includes(profile)) return false;
        error = "";
        PowerProfiles.profile = profile === "power-saver" ? PowerProfile.PowerSaver
            : profile === "performance" ? PowerProfile.Performance : PowerProfile.Balanced;
        return true;
    }
}

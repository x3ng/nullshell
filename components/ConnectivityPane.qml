pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: pane
    required property Theme style
    required property var services
    required property string section
    required property bool active
    property bool retainContent: false
    readonly property var system: services.controls
    readonly property bool wifi: section === "wifi"
    readonly property bool radioEnabled: wifi ? system.wifiEnabled : system.bluetoothEnabled
    // Visible content may outlive active briefly during the panel exit fade.
    // Hidden panes must not retain/rebuild native device delegates.
    readonly property var rows: (active || retainContent) && (wifi || section === "bluetooth") && radioEnabled
        ? (wifi ? system.wifiNearbyNetworks : system.bluetoothDevices) : []
    property string selectedKey: ""
    property bool confirmForget: false
    readonly property var selectedDevice: rows.find(device => key(device) === selectedKey) ?? null
    readonly property bool selectedBusy: selectedDevice ? (wifi ? system.wifiBusy : system.bluetoothDeviceBusy(selectedDevice)) : false
    readonly property bool passwordNeeded: wifi && !!selectedDevice && !selectedDevice.connected && system.wifiUsesPassword(selectedDevice)
    readonly property string failure: wifi ? system.wifiError : system.bluetoothError
    signal revealRequested()
    spacing: style.spaceSm

    function key(device) { return wifi ? system.wifiKey(device) : system.bluetoothKey(device); }
    function reset() {
        selectedKey = "";
        confirmForget = false;
        password.clear(); password.revealed = false;
        pairingInput.clear();
        system.stopBluetoothScan();
        system.cancelBluetoothPairing();
    }
    onActiveChanged: { if (!active) reset(); }
    onSectionChanged: reset()
    onRadioEnabledChanged: { if (!radioEnabled) reset(); }
    onSelectedDeviceChanged: { if (!selectedDevice) { password.clear(); confirmForget = false; } }
    function select(device) {
        selectedKey = key(device);
        confirmForget = false;
        password.clear(); password.revealed = false;
        if (wifi) system.clearWifiError();
        else system.clearBluetoothError();
        revealRequested();
        Qt.callLater(() => { if (pane.active && pane.passwordNeeded && !device.known) password.forceActiveFocus(); });
    }
    function connectSelected() {
        if (!selectedDevice || selectedBusy) return;
        const accepted = wifi ? system.connectWifi(selectedDevice, password.text)
            : selectedDevice.paired ? system.toggleBluetoothDevice(selectedDevice) : system.pairBluetooth(selectedDevice);
        if (accepted) { password.clear(); password.revealed = false; }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: !pane.wifi && pane.radioEnabled
        Text {
            Layout.fillWidth: true
            text: pane.system.bluetoothScanRequested ? "Searching for devices…" : "Paired & nearby devices"
            color: pane.style.textMuted
            font.family: pane.style.fontFamily
            font.pixelSize: pane.style.fontSizeSmall
        }
        ChoiceButton {
            Layout.preferredWidth: 108
            style: pane.style
            label: pane.system.bluetoothScanRequested ? "Stop search" : "Search devices"
            filled: true
            selected: pane.system.bluetoothScanRequested
            onTriggered: pane.system.toggleBluetoothScan()
        }
    }

    GroupCard {
        Layout.fillWidth: true
        visible: !pane.wifi && !!pane.system.pairingDevice
        style: pane.style
        border.color: pane.style.accent
        Text {
            Layout.fillWidth: true
            text: "Pair with " + (pane.system.pairingDevice?.name || pane.system.pairingDevice?.address || "device")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: pane.style.textPrimary
            font.family: pane.style.fontFamily
            font.pixelSize: pane.style.fontSizeControl
            font.weight: Font.DemiBold
        }
        Text {
            Layout.fillWidth: true
            text: pane.system.pairingPrompt === "confirm" ? "Does this code match the other device?"
                : pane.system.pairingPrompt === "display" ? "Type this code on the other device, then press Enter there."
                : pane.system.pairingPrompt === "pin" ? "Enter the device PIN."
                : pane.system.pairingPrompt === "passkey" ? "Enter the passkey shown on the other device."
                : pane.system.pairingPrompt === "authorize" ? "Allow this device to pair or use the requested service?"
                : "Keep the device in pairing mode. Waiting for a response…"
            wrapMode: Text.Wrap
            color: pane.style.textSecondary
            font.family: pane.style.fontFamily
            font.pixelSize: pane.style.fontSizeSmall
        }
        Text {
            Layout.fillWidth: true
            visible: pane.system.pairingCode !== "" && ["confirm", "display"].includes(pane.system.pairingPrompt)
            text: pane.system.pairingCode
            textFormat: Text.PlainText
            color: pane.style.accent
            font.family: pane.style.fontFamily
            font.pixelSize: 28
            font.letterSpacing: 5
        }
        ConnectionField {
            id: pairingInput
            objectName: "pairingInput"
            Layout.fillWidth: true
            style: pane.style
            visible: ["pin", "passkey"].includes(pane.system.pairingPrompt)
            placeholderText: pane.system.pairingPrompt === "pin" ? "PIN" : "Passkey"
            maximumLength: pane.system.pairingPrompt === "pin" ? 16 : 6
            onAccepted: { if (pane.system.answerBluetoothPairing(text)) clear(); }
        }
        RowLayout {
            Layout.fillWidth: true
            ChoiceButton {
                Layout.fillWidth: true
                style: pane.style
                label: "Cancel pairing"
                onTriggered: pane.system.cancelBluetoothPairing()
            }
            ChoiceButton {
                Layout.fillWidth: true
                style: pane.style
                filled: true
                selected: true
                visible: ["confirm", "authorize", "pin", "passkey"].includes(pane.system.pairingPrompt)
                label: ["confirm", "authorize"].includes(pane.system.pairingPrompt) ? "Confirm" : "Submit code"
                available: ["confirm", "authorize"].includes(pane.system.pairingPrompt) || pairingInput.text.length > 0
                onTriggered: {
                    const answer = ["confirm", "authorize"].includes(pane.system.pairingPrompt) ? "yes" : pairingInput.text;
                    if (pane.system.answerBluetoothPairing(answer)) pairingInput.clear();
                }
            }
        }
    }
    Connections {
        target: pane.system
        function onPairingPromptChanged() {
            pairingInput.clear();
            if (!pane.active) return;
            pane.revealRequested();
            Qt.callLater(() => { if (pane.active && pairingInput.visible) pairingInput.forceActiveFocus(); });
        }
    }

    GroupCard {
        Layout.fillWidth: true
        visible: !!pane.selectedDevice && pane.system.pairingDevice !== pane.selectedDevice
        style: pane.style
        border.color: pane.style.accent
        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: pane.selectedDevice?.name || pane.selectedDevice?.address || ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: pane.style.textPrimary
                font.family: pane.style.fontFamily
                font.pixelSize: pane.style.fontSizeControl
                font.weight: Font.DemiBold
            }
            ChoiceButton {
                Layout.preferredWidth: 28
                style: pane.style
                label: ""
                iconKind: "close"
                onTriggered: { pane.selectedKey = ""; password.clear(); }
            }
        }
        Text {
            Layout.fillWidth: true
            text: !pane.selectedDevice ? "" : pane.wifi
                ? pane.system.wifiNetworkLabel(pane.selectedDevice) + " · " + pane.selectedDevice.device.name
                : pane.selectedDevice.address + " · " + pane.system.bluetoothDeviceLabel(pane.selectedDevice)
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: pane.style.textMuted
            font.family: pane.style.fontFamily
            font.pixelSize: pane.style.fontSizeSmall
        }
        ConnectionField {
            id: password
            objectName: "wifiPassword"
            Layout.fillWidth: true
            style: pane.style
            secret: true
            visible: pane.passwordNeeded
            placeholderText: pane.selectedDevice?.known ? "Saved password · type to replace" : "Wi-Fi password"
            maximumLength: 64
            enabled: !pane.selectedBusy
            onAccepted: pane.connectSelected()
        }
        Text {
            Layout.fillWidth: true
            visible: pane.wifi && !!pane.selectedDevice && !pane.system.wifiCanJoin(pane.selectedDevice)
            text: "Enterprise or legacy authentication needs advanced network settings below."
            wrapMode: Text.Wrap
            color: pane.style.accentWarm
            font.family: pane.style.fontFamily
            font.pixelSize: pane.style.fontSizeSmall
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: pane.style.spaceSm
            ChoiceButton {
                Layout.fillWidth: true
                style: pane.style
                filled: true
                selected: true
                label: pane.selectedBusy ? "Working…" : pane.selectedDevice?.connected ? "Disconnect"
                    : !pane.wifi && !pane.selectedDevice?.paired ? "Pair & connect" : "Connect"
                available: !!pane.selectedDevice && !pane.selectedBusy
                    && (!pane.wifi || pane.selectedDevice.connected || (pane.system.wifiCanJoin(pane.selectedDevice)
                        && (!pane.passwordNeeded || (pane.selectedDevice.known && password.text === "")
                            || pane.system.wifiPasswordValid(pane.selectedDevice, password.text))))
                onTriggered: {
                    if (pane.wifi && pane.selectedDevice.connected) pane.system.disconnectWifi(pane.selectedDevice);
                    else pane.connectSelected();
                }
            }
            ChoiceButton {
                Layout.fillWidth: true
                style: pane.style
                label: pane.confirmForget ? "Confirm forget" : "Forget"
                tone: pane.confirmForget ? "danger" : "neutral"
                visible: pane.wifi ? (pane.selectedDevice?.known ?? false) : (pane.selectedDevice?.paired ?? false)
                available: !pane.selectedBusy
                onTriggered: {
                    if (!pane.confirmForget) { pane.confirmForget = true; return; }
                    const accepted = pane.wifi ? pane.system.forgetWifi(pane.selectedDevice) : pane.system.forgetBluetooth(pane.selectedDevice);
                    if (accepted) { pane.selectedKey = ""; password.clear(); }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: pane.failure !== ""
        text: pane.failure
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: pane.style.accentWarm
        font.family: pane.style.fontFamily
        font.pixelSize: pane.style.fontSizeSmall
    }
    Repeater {
        model: pane.rows
        delegate: DeviceRow {
            required property var modelData
            Layout.fillWidth: true
            style: pane.style
            title: modelData.name || modelData.address
            subtitle: pane.wifi ? pane.system.wifiNetworkLabel(modelData) : pane.system.bluetoothDeviceLabel(modelData)
            selected: modelData.connected
            expanded: pane.key(modelData) === pane.selectedKey
            iconKind: pane.wifi ? "wifi" : "bluetooth"
            onTriggered: pane.select(modelData)
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.preferredHeight: 64
        visible: pane.rows.length === 0
        text: !pane.radioEnabled ? (pane.wifi ? "Turn on Wi-Fi to see nearby networks" : "Turn on Bluetooth to manage devices")
            : pane.wifi ? "Looking for nearby networks…" : "Search for devices with pairing mode enabled"
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: pane.style.textMuted
        font.family: pane.style.fontFamily
        font.pixelSize: pane.style.fontSizeSmall
    }
    ChoiceButton {
        Layout.fillWidth: true
        visible: pane.wifi
        style: pane.style
        label: "Advanced network settings…"
        available: pane.services.terminalCommand.length > 0
        onTriggered: pane.services.openNetworkEditor()
    }
}

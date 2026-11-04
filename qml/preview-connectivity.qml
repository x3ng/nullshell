import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "components"

// Visual fixtures only: no system adapters, notifications or idle policy.
ShellRoot {
    Theme { id: theme; darkMode: !light.checked }
    QtObject {
        id: fixture
        readonly property bool wifiAvailable: scenario.currentIndex !== 4
        readonly property bool bluetoothAvailable: wifiAvailable
        readonly property bool wifiEnabled: scenario.currentIndex !== 3
        readonly property bool bluetoothEnabled: wifiEnabled
        readonly property bool connected: scenario.currentIndex < 2
        readonly property string wifiConnection: connected ? "Studio Wi-Fi" : "Not connected"
        readonly property var wifiNetworks: connected ? [{name: wifiConnection, connected: true, signalStrength: 0.86}] : []
        readonly property var bluetoothDevices: !connected ? [] : scenario.currentIndex === 1
            ? [{name: "A deliberately long Bluetooth headphone name", connected: true, batteryAvailable: true, battery: 0.72},
               {name: "Mouse", connected: true, batteryAvailable: false}]
            : [{name: "Headphones", connected: true, batteryAvailable: true, battery: 0.72}]
        readonly property var bluetoothConnected: bluetoothDevices
        function execute(action) { feedback.text = "Open " + action + " (preview only)"; }
    }
    FloatingWindow {
        visible: true
        implicitWidth: 780
        implicitHeight: 240
        title: "nullshell · Connectivity preview"
        color: theme.backgroundSurface
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16
            RowLayout {
                ComboBox {
                    id: scenario
                    model: ["Connected", "Multiple devices / long name", "Disconnected", "Radio off", "Unavailable"]
                    Layout.fillWidth: true
                }
                CheckBox { id: light; text: "Light"; checked: Quickshell.env("QS_PREVIEW_LIGHT") === "1" }
            }
            MaterialSurface {
                materialTheme: theme
                Layout.fillWidth: true
                implicitHeight: summary.implicitHeight + 24
                ConnectivitySummary {
                    id: summary
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                    style: theme
                    system: fixture
                    actions: fixture
                }
            }
            Label { id: feedback; text: "Resize to check truncation · source edits reload automatically"; color: theme.textSecondary }
            Item { Layout.fillHeight: true }
        }
    }
}

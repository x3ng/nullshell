pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import ".."

RowLayout {
    id: status
    required property Theme style
    required property var services
    required property date date
    property bool expanded: true
    readonly property bool hasBattery: services.battery?.isPresent ?? false
    readonly property string powerState: services.batteryDetail(services.battery)
    spacing: 6
        RowLayout {
            id: statusClock
            Layout.leftMargin: 0
            Layout.rightMargin: 6
            spacing: 12
            Text {
                text: Qt.formatDateTime(status.date, "HH:mm")
                color: status.style.textPrimary
                font.family: status.style.fontFamily
                font.pixelSize: 18
                font.weight: Font.DemiBold
            }
            Text {
                text: Qt.formatDateTime(status.date, status.expanded ? "MMM d, ddd" : "M/d")
                color: status.style.textSecondary
                font.family: status.style.fontFamily
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            HoverHandler { id: clockHover }
            ShellToolTip {
                style: status.style
                visible: clockHover.hovered
                text: Qt.formatDateTime(status.date, "dddd, MMMM d, yyyy")
            }
        }
        Item {
            id: powerLabel
            visible: status.hasBattery
            Layout.preferredWidth: batteryContents.implicitWidth + 12
            Layout.preferredHeight: 36
            Accessible.name: "Battery " + Math.round((status.services.battery?.percentage ?? 0) * 100) + "% · " + status.powerState
            RowLayout {
                id: batteryContents
                anchors.centerIn: parent
                spacing: 8
                BatteryGlyph {
                    level: status.services.battery?.percentage ?? 0
                    charging: status.services.battery?.state === UPowerDeviceState.Charging
                    ink: level < 0.2 ? status.style.accentWarm : status.style.textPrimary
                    surface: status.style.panelSurface
                }
                Text {
                    text: Math.round((status.services.battery?.percentage ?? 0) * 100) + "%"
                    color: status.style.textPrimary
                    font.family: status.style.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }
            }
            HoverHandler { id: powerHover }
            ShellToolTip {
                style: status.style
                visible: powerHover.hovered
                text: status.services.batteryDetail(status.services.battery)
            }
        }
}

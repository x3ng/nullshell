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
    spacing: style.spaceMd
        RowLayout {
            id: statusClock
            spacing: status.style.spaceSm
            Text {
                text: Qt.formatDateTime(status.date, "HH:mm")
                color: status.style.textPrimary
                font.family: status.style.fontFamily
                font.pixelSize: status.style.fontSizeLabel
                font.weight: Font.Medium
            }
            Text {
                text: Qt.formatDateTime(status.date, status.expanded ? "MMM d, ddd" : "M/d")
                color: status.style.textSecondary
                font.family: status.style.fontFamily
                font.pixelSize: status.style.fontSizeLabel
                font.weight: Font.Normal
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
            Layout.preferredWidth: batteryContents.implicitWidth
            Layout.preferredHeight: batteryContents.implicitHeight
            Accessible.name: "Battery " + Math.round((status.services.battery?.percentage ?? 0) * 100) + "% · " + status.powerState
            RowLayout {
                id: batteryContents
                anchors.centerIn: parent
                spacing: status.style.spaceXs
                BatteryGlyph {
                    level: status.services.battery?.percentage ?? 0
                    charging: status.services.battery?.state === UPowerDeviceState.Charging
                    ink: level < 0.2 ? status.style.accentWarm : status.style.textSecondary
                    surface: status.style.panelSurface
                }
                Text {
                    text: Math.round((status.services.battery?.percentage ?? 0) * 100) + "%"
                    color: (status.services.battery?.percentage ?? 1) < 0.2 ? status.style.accentWarm : status.style.textSecondary
                    font.family: status.style.fontFamily
                    font.pixelSize: status.style.fontSizeLabel
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

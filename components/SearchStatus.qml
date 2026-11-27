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
    spacing: style.spaceSm

    RowLayout {
        id: statusClock
        spacing: 6
        Text {
            text: Qt.formatDateTime(status.date, "HH:mm")
            color: status.style.textPrimary
            font.family: status.style.fontFamily
            font.pixelSize: status.style.fontSizeSearch
            font.weight: Font.Bold
        }
        Text {
            text: Qt.formatDateTime(status.date, status.expanded ? "ddd, MMM d" : "MMM d")
            color: status.style.textMuted
            font.family: status.style.fontFamily
            font.pixelSize: status.style.fontSizeLabel
            font.weight: Font.Medium
        }
        HoverHandler { id: clockHover }
        ShellToolTip {
            style: status.style
            visible: clockHover.hovered
            text: Qt.formatDateTime(status.date, "dddd, MMMM d, yyyy")
        }
    }

    Rectangle {
        visible: status.hasBattery
        Layout.preferredWidth: 3
        Layout.preferredHeight: 3
        radius: 1.5
        color: status.style.outline
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
            spacing: 4
            BatteryGlyph {
                level: status.services.battery?.percentage ?? 0
                charging: status.services.battery?.state === UPowerDeviceState.Charging
                ink: level < 0.2 ? status.style.accentWarm : status.style.textSecondary
                surface: status.style.inputSurface
            }
            Text {
                text: Math.round((status.services.battery?.percentage ?? 0) * 100) + "%"
                color: (status.services.battery?.percentage ?? 1) < 0.2 ? status.style.accentWarm : status.style.textSecondary
                font.family: status.style.fontFamily
                font.pixelSize: status.style.fontSizeLabel
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

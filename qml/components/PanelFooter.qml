pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.UPower
import ".."

Rectangle {
    id: footer
    required property Theme style
    required property var services
    required property var appearance
    required property var trayItems
    property bool searchMode: false
    property bool summaryOnly: false
    property bool centerActions: false
    property int notificationCount: 0
    property int notificationHistoryCount: 0
    property bool lockAvailable: false
    signal notificationsRequested()
    signal lockRequested()
    signal appearanceRequested()
    signal keepAwakeRequested()
    required property date date
    signal menuRequested(var owner, real right, real top)

    readonly property bool hasBattery: services.battery?.isPresent ?? false
    readonly property string powerState: {
        const state = services.battery?.state;
        if (state === UPowerDeviceState.Charging) return "Charging";
        if (state === UPowerDeviceState.FullyCharged) return "Fully charged";
        if (state === UPowerDeviceState.Discharging) return width < 500 ? "Battery" : "On battery";
        if (state === UPowerDeviceState.PendingCharge) return "Plugged in";
        if (state === UPowerDeviceState.Empty) return "Empty";
        return "Battery";
    }
    implicitHeight: 48
    color: "transparent"

    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 1
        color: footer.style.separator
    }

    RowLayout {
        visible: footer.searchMode
        anchors.fill: parent
        anchors.topMargin: 9
        anchors.bottomMargin: 3
        spacing: 18
        Repeater {
            model: ["↑ ↓  Navigate", "esc  Back"]
            Text {
                required property string modelData
                text: modelData
                font.family: footer.style.fontFamily
                font.pixelSize: footer.style.fontSizeSmall
                color: footer.style.textMuted
            }
        }
        Item { Layout.fillWidth: true }
    }

    RowLayout {
        visible: !footer.searchMode
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 10
        width: Math.min(implicitWidth, footer.width)
        height: 36
        spacing: 6
        UtilityButton {
            id: appearanceButton
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            style: footer.style
            label: ""
            iconKind: footer.appearance.darkMode ? "moon" : "brightness"
            iconSize: 20
            available: footer.appearance.appearanceAvailable
            tooltip: footer.appearance.darkMode ? "Switch to light appearance" : "Switch to dark appearance"
            onTriggered: footer.appearanceRequested()
        }
        UtilityButton {
            id: awakeButton
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            style: footer.style
            label: ""
            iconKind: "coffee"
            iconSize: 20
            checkable: true
            selected: footer.services.keepAwake
            tooltip: footer.services.keepAwake ? "Keep awake: on · Click to resume idle" : "Keep awake: off · Click to prevent idle"
            onTriggered: footer.keepAwakeRequested()
        }
        UtilityButton {
            id: lockButton
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            style: footer.style
            label: ""
            iconKind: "lock"
            iconSize: 20
            tooltip: "Lock screen"
            available: footer.lockAvailable
            onTriggered: footer.lockRequested()
        }
        Rectangle {
            visible: footer.trayItems.length > 0
            width: 1; height: 22
            color: footer.style.separator
        }
        Flickable {
            id: trayViewport
            objectName: "footer-tray-viewport"
            visible: footer.trayItems.length > 0
            Layout.preferredWidth: Math.min(trayRow.implicitWidth, Math.max(0, footer.width - appearanceButton.width - awakeButton.width - lockButton.width - 37))
            Layout.maximumWidth: Layout.preferredWidth
            Layout.preferredHeight: 36
            contentWidth: trayRow.implicitWidth
            contentHeight: 36
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            function clampScroll() { contentX = Math.max(0, Math.min(contentX, contentWidth - width)); }
            onContentWidthChanged: clampScroll()
            onWidthChanged: clampScroll()
            ScrollBar.horizontal: ScrollBar {
                policy: ScrollBar.AsNeeded
                height: 3
                contentItem: Rectangle {
                    implicitHeight: 3
                    radius: 1.5
                    color: footer.style.textMuted
                }
                background: Item {}
            }
            WheelHandler {
                target: null
                onWheel: event => {
                    if (trayViewport.contentWidth <= trayViewport.width) return;
                    const pixels = event.pixelDelta.x || event.pixelDelta.y;
                    const delta = pixels || (event.angleDelta.x || event.angleDelta.y) / 120 * 32;
                    trayViewport.contentX = Math.max(0, Math.min(trayViewport.contentWidth - trayViewport.width,
                        trayViewport.contentX - delta));
                    event.accepted = true;
                }
            }
            Row {
                id: trayRow
                spacing: footer.style.spaceXs
                Repeater {
                    model: footer.trayItems
                    Rectangle {
                        id: trayItem
                        required property var modelData
                        width: 36; height: 36
                        radius: footer.style.radiusControl
                        color: trayMouse.containsMouse ? footer.style.surfaceHover : "transparent"
                        IconImage {
                            id: trayIcon
                            anchors.centerIn: parent
                            implicitSize: 20
                            source: trayItem.modelData.icon
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !trayIcon.visible
                            text: (trayItem.modelData.title || trayItem.modelData.id || "?").slice(0, 1)
                            color: footer.style.textSecondary
                            font.pixelSize: footer.style.fontSizeBody
                        }
                        MouseArea {
                            id: trayMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: event => {
                                if (event.button === Qt.RightButton || trayItem.modelData.onlyMenu) {
                                    const pos = trayItem.mapToItem(footer, trayItem.width, 0);
                                    footer.menuRequested(trayItem.modelData, pos.x, pos.y);
                                } else trayItem.modelData.activate();
                            }
                        }
                        ShellToolTip {
                            style: footer.style
                            visible: trayMouse.containsMouse && text !== ""
                            text: [trayItem.modelData.tooltipTitle || trayItem.modelData.title || trayItem.modelData.id || "",
                                trayItem.modelData.tooltipDescription || ""].filter(part => part !== "").join("\n")
                        }
                    }
                }
            }
        }
    }
}

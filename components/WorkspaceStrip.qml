pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Widgets
import ".."

Item {
    id: strip
    required property Theme style
    required property var controls
    required property var searchModel
    required property var workspaces
    required property var windows
    property var trayItems: []
    signal menuRequested(var owner, real right, real top)
    implicitHeight: entries.implicitHeight
    // Center a short group; let a larger group wrap within the available width.
    readonly property real contentSpan: {
        const chips = entries.children.filter(child => child.width > 0 && child.visible);
        return chips.reduce((sum, child) => sum + child.width, 0) + Math.max(0, chips.length - 1) * entries.spacing;
    }
    Flow {
        id: entries
        width: Math.min(strip.width, strip.contentSpan)
        x: (strip.width - width) / 2
        spacing: 3
        Repeater {
            model: strip.workspaces
            ChoiceButton {
                id: chip
                required property var modelData
                readonly property bool special: modelData.special || String(modelData.address).startsWith("special:")
                readonly property var apps: strip.windows.filter(w => w.workspaceAddress === modelData.address)
                width: contents.implicitWidth + 14
                height: 32
                style: strip.style
                label: ""
                tone: "toggle"
                selected: modelData.address === strip.controls.focusedWorkspaceAddress
                available: strip.controls.available && !strip.controls.busy
                tooltip: (special ? "Special workspace " : "Workspace ") + String(modelData.name).replace(/^special:/, "") + " · " + apps.length + (apps.length === 1 ? " window" : " windows")
                Accessible.name: tooltip
                onTriggered: strip.controls.focusWorkspace(modelData.address)
                Row {
                    id: contents
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        height: 28
                        verticalAlignment: Text.AlignVCenter
                        text: chip.special ? "$" : String(chip.modelData.name)
                        textFormat: Text.PlainText
                        font.family: strip.style.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        color: chip.selected ? strip.style.textPrimary : strip.style.textSecondary
                        width: Math.min(implicitWidth, 64)
                        elide: Text.ElideRight
                    }
                    Repeater {
                        model: chip.apps.slice(0, 3)
                        Item {
                            required property var modelData
                            width: 16; height: 28
                            IconImage {
                                id: appIcon
                                anchors.centerIn: parent
                                implicitSize: 16
                                source: strip.searchModel.desktopIconSource(strip.searchModel.desktopEntryFor(modelData))
                                visible: status === Image.Ready
                            }
                            StatusIcon {
                                anchors.centerIn: parent
                                width: 16; height: 16
                                kind: "window"
                                ink: strip.style.textMuted
                                visible: !appIcon.visible
                            }
                        }
                    }
                    Text {
                        visible: chip.apps.length > 3
                        height: 28
                        verticalAlignment: Text.AlignVCenter
                        text: "+" + (chip.apps.length - 3)
                        color: strip.style.textMuted
                        font.family: strip.style.fontFamily
                        font.pixelSize: 13
                    }
                }
            }
        }
        Repeater {
            model: strip.trayItems
            Rectangle {
                id: trayItem
                required property var modelData
                required property int index
                readonly property int leadingSpace: index === 0 && strip.workspaces.length > 0 ? 8 : 0
                width: 26 + leadingSpace; height: 32
                radius: strip.style.radiusControl
                color: "transparent"
                Rectangle {
                    visible: trayItem.leadingSpace > 0
                    width: 1; height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    color: strip.style.textMuted
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: trayItem.leadingSpace
                    anchors.topMargin: 4
                    anchors.bottomMargin: 4
                    radius: strip.style.radiusControl
                    color: trayMouse.containsMouse ? strip.style.surfaceHover : "transparent"
                }
                IconImage {
                    id: trayIcon
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: trayItem.leadingSpace / 2
                    implicitSize: 16
                    source: trayItem.modelData.icon
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: trayItem.leadingSpace / 2
                    visible: !trayIcon.visible
                    text: (trayItem.modelData.title || trayItem.modelData.id || "?").slice(0, 1)
                    color: strip.style.textSecondary
                    font.pixelSize: strip.style.fontSizeBody
                }
                MouseArea {
                    id: trayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: event => {
                        if (event.button === Qt.RightButton || trayItem.modelData.onlyMenu) {
                            const pos = trayItem.mapToItem(strip, trayItem.width, 0);
                            strip.menuRequested(trayItem.modelData, pos.x, pos.y);
                        } else trayItem.modelData.activate();
                    }
                }
                ShellToolTip {
                    style: strip.style
                    visible: trayMouse.containsMouse && text !== ""
                    text: [trayItem.modelData.tooltipTitle || trayItem.modelData.title || trayItem.modelData.id || "",
                        trayItem.modelData.tooltipDescription || ""].filter(part => part !== "").join("\n")
                }
            }
        }
    }
}

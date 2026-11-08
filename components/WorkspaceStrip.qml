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
        spacing: 6
        Repeater {
            model: strip.workspaces
            ChoiceButton {
                id: chip
                required property var modelData
                readonly property var apps: strip.windows.filter(w => w.workspaceAddress === modelData.address)
                width: contents.implicitWidth + 22
                height: 44
                style: strip.style
                label: ""
                tone: "toggle"
                selected: modelData.address === strip.controls.focusedWorkspaceAddress
                available: strip.controls.available && !strip.controls.busy
                tooltip: "Workspace " + modelData.name + " · " + apps.length + (apps.length === 1 ? " window" : " windows")
                Accessible.name: tooltip
                onTriggered: strip.controls.focusWorkspace(modelData.address)
                Row {
                    id: contents
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        height: 28
                        verticalAlignment: Text.AlignVCenter
                        text: String(chip.modelData.name).replace(/^special:/, "")
                        textFormat: Text.PlainText
                        font.family: strip.style.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.Medium
                        color: chip.selected ? strip.style.textPrimary : strip.style.textSecondary
                        width: Math.min(implicitWidth, 64)
                        elide: Text.ElideRight
                    }
                    Repeater {
                        model: chip.apps.slice(0, 3)
                        Item {
                            required property var modelData
                            width: 20; height: 28
                            IconImage {
                                id: appIcon
                                anchors.centerIn: parent
                                implicitSize: 20
                                source: strip.searchModel.desktopIconSource(strip.searchModel.desktopEntryFor(modelData))
                                visible: status === Image.Ready
                            }
                            StatusIcon {
                                anchors.centerIn: parent
                                width: 20; height: 20
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
    }
}

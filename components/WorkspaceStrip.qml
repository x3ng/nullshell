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
    property Component toolsComponent: null
    signal menuRequested(var owner, real right, real top)
    // Within a group, between groups, and between wrapped rows.
    readonly property int itemGap: style.spaceXs
    readonly property int groupGap: style.spaceMd
    readonly property int rowGap: style.spaceXs
    // The parent owns space to the separator and outer edge.
    implicitHeight: Math.max(style.stripHeight - 2 * style.spaceMd, footer.implicitHeight)
    Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        implicitHeight: entries.implicitHeight
        Item {
            id: entries
            objectName: "footer-entries"
            width: parent.width
            // Flow only centers its bounding box. Pack and center each row so
            // the last, shorter row stays balanced as workspaces come and go.
            readonly property var rows: {
                const result = [];
                let row = {items: [], width: 0, height: 0};
                for (const child of children) {
                    if (!child.visible || child.width <= 0 || child.height <= 0) continue;
                    let gap = row.items.length ? (row.items[row.items.length - 1].item.group === child.group ? strip.itemGap : strip.groupGap) : 0;
                    if (row.items.length && row.width + gap + child.width > width) {
                        result.push(row);
                        row = {items: [], width: 0, height: 0};
                        gap = 0;
                    }
                    row.items.push({item: child, offset: row.width + gap});
                    row.width += gap + child.width;
                    row.height = Math.max(row.height, child.height);
                }
                if (row.items.length) result.push(row);
                return result;
            }
            implicitHeight: rows.reduce((height, row) => height + row.height, 0) + Math.max(0, rows.length - 1) * strip.rowGap
            function arrange() {
                let top = 0;
                for (const row of rows) {
                    for (const cell of row.items) {
                        cell.item.x = (width - row.width) / 2 + cell.offset;
                        cell.item.y = top + (row.height - cell.item.height) / 2;
                    }
                    top += row.height + strip.rowGap;
                }
            }
            onRowsChanged: arrange()
            onWidthChanged: arrange()
            Component.onCompleted: arrange()
            Repeater {
                model: strip.workspaces
                ChoiceButton {
                    id: chip
                    readonly property string group: "workspace"
                    required property var modelData
                    readonly property bool special: modelData.special || String(modelData.address).startsWith("special:")
                    readonly property var apps: strip.windows.filter(w => w.workspaceAddress === modelData.address)
                    // Identifiable icons are shown; windows without one collapse into a
                    // single generic glyph and a count instead of a run of identical boxes.
                    readonly property var known: apps.filter(w => strip.searchModel.desktopIconSource(strip.searchModel.desktopEntryFor(w)) !== "")
                    readonly property var shown: known.slice(0, 3)
                    readonly property int generic: apps.length - shown.length
                    width: contents.implicitWidth + 2 * strip.style.spaceSm
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
                            font.pixelSize: strip.style.fontSizeSmall
                            font.weight: Font.Medium
                            color: chip.selected ? strip.style.textPrimary : strip.style.textSecondary
                            width: Math.min(implicitWidth, 64)
                            elide: Text.ElideRight
                        }
                        Repeater {
                            model: chip.shown
                            Item {
                                required property var modelData
                                width: 16; height: 28
                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: 16
                                    source: strip.searchModel.desktopIconSource(strip.searchModel.desktopEntryFor(modelData))
                                }
                            }
                        }
                        Item {
                            visible: chip.generic > 0
                            width: 14; height: 28
                            StatusIcon {
                                anchors.centerIn: parent
                                width: 14; height: 14
                                kind: "window"
                                ink: strip.style.textMuted
                            }
                        }
                        Text {
                            // Count the windows not shown as an icon; one generic window needs no number.
                            visible: chip.generic > 1 || (chip.generic > 0 && chip.shown.length > 0)
                            height: 28
                            verticalAlignment: Text.AlignVCenter
                            text: chip.shown.length ? "+" + chip.generic : String(chip.generic)
                            color: strip.style.textMuted
                            font.family: strip.style.fontFamily
                            font.pixelSize: strip.style.fontSizeLabel
                        }
                    }
                }
            }
            Repeater {
                model: strip.trayItems
                Rectangle {
                    id: trayItem
                    readonly property string group: "tray"
                    required property var modelData
                    required property int index
                    objectName: "tray-item-" + index
                    activeFocusOnTab: visible
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.tooltipTitle || modelData.title || modelData.id || "Tray item"
                    Accessible.onPressAction: trayItem.triggered()
                    border.width: activeFocus ? strip.style.focusWidth : 0
                    border.color: strip.style.focusInk
                    function openMenu() {
                        const pos = trayItem.mapToItem(strip, width, 0);
                        strip.menuRequested(modelData, pos.x, pos.y);
                    }
                    function triggered() {
                        if (modelData.onlyMenu) openMenu();
                        else modelData.activate();
                    }
                    Keys.onReturnPressed: triggered()
                    Keys.onEnterPressed: triggered()
                    Keys.onSpacePressed: triggered()
                    Keys.onMenuPressed: openMenu()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier)) {
                            openMenu(); event.accepted = true;
                        }
                    }
                    width: 32; height: 32
                    radius: strip.style.radiusControl
                    // Hover uses the full target, like neighbouring footer controls.
                    color: trayMouse.containsMouse ? strip.style.surfaceHover : "transparent"
                    IconImage {
                        id: trayIcon
                        anchors.centerIn: parent
                        implicitSize: 16
                        source: trayItem.modelData.icon
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
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
                            if (event.button === Qt.RightButton) trayItem.openMenu();
                            else trayItem.triggered();
                        }
                    }
                    ShellToolTip {
                        style: strip.style
                        visible: (trayMouse.containsMouse || trayItem.activeFocus) && text !== ""
                        text: [trayItem.modelData.tooltipTitle || trayItem.modelData.title || trayItem.modelData.id || "",
                            trayItem.modelData.tooltipDescription || ""].filter(part => part !== "").join("\n")
                    }
                }
            }
            Loader {
                id: toolsLoader
                objectName: "footer-tools"
                readonly property string group: "tools"
                sourceComponent: strip.toolsComponent
            }
        }
    }
}

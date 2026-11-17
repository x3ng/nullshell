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
                    let gap = row.items.length ? (row.items[row.items.length - 1].item.group === child.group ? 3 : 8) : 0;
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
            implicitHeight: rows.reduce((height, row) => height + row.height, 0) + Math.max(0, rows.length - 1) * 3
            function arrange() {
                let top = 0;
                for (const row of rows) {
                    for (const cell of row.items) {
                        cell.item.x = (width - row.width) / 2 + cell.offset;
                        cell.item.y = top + (row.height - cell.item.height) / 2;
                    }
                    top += row.height + 3;
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
                    readonly property string group: "tray"
                    required property var modelData
                    required property int index
                    objectName: "tray-item-" + index
                    activeFocusOnTab: visible
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.tooltipTitle || modelData.title || modelData.id || "Tray item"
                    Accessible.onPressAction: trayItem.triggered()
                    border.width: activeFocus ? 1 : 0
                    border.color: strip.style.accent
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
                    color: "transparent"
                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: 4
                        anchors.bottomMargin: 4
                        radius: strip.style.radiusControl
                        color: trayMouse.containsMouse ? strip.style.surfaceHover : "transparent"
                    }
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

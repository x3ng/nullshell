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

    readonly property int itemGap: 4
    readonly property int groupGap: 10
    readonly property int rowGap: 4
    readonly property int dividerGap: 8

    implicitHeight: divider.height + dividerGap + Math.max(32, footer.implicitHeight)

    Rectangle {
        id: divider
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: strip.style.separator
        opacity: 0.75
    }

    Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: divider.bottom
        anchors.topMargin: strip.dividerGap
        implicitHeight: entries.implicitHeight

        Item {
            id: entries
            objectName: "footer-entries"
            width: parent.width

            // Single row: anchor workspaces left, tray + system tools right so the
            // footer frames the panel edges cleanly. Overflowing narrow rows wrap neatly.
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
                if (rows.length === 1) {
                    const row = rows[0];
                    const leftItems = row.items.filter(cell => cell.item.group === "workspace");
                    const rightItems = row.items.filter(cell => cell.item.group !== "workspace");
                    let leftX = 0;
                    for (const cell of leftItems) {
                        cell.item.x = leftX;
                        cell.item.y = (row.height - cell.item.height) / 2;
                        leftX += cell.item.width + strip.itemGap;
                    }
                    let rightWidth = 0;
                    for (let i = 0; i < rightItems.length; i++) {
                        if (i > 0) rightWidth += rightItems[i - 1].item.group === rightItems[i].item.group ? strip.itemGap : strip.groupGap;
                        rightWidth += rightItems[i].item.width;
                    }
                    let rightX = Math.max(leftX, width - rightWidth);
                    for (let i = 0; i < rightItems.length; i++) {
                        const cell = rightItems[i];
                        if (i > 0) rightX += rightItems[i - 1].item.group === cell.item.group ? strip.itemGap : strip.groupGap;
                        cell.item.x = rightX;
                        cell.item.y = (row.height - cell.item.height) / 2;
                        rightX += cell.item.width;
                    }
                    return;
                }
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
                    readonly property var known: apps.filter(w => strip.searchModel.desktopIconSource(strip.searchModel.desktopEntryFor(w)) !== "")
                    readonly property var shown: known.slice(0, 3)
                    readonly property int generic: apps.length - shown.length
                    width: Math.max(30, contents.implicitWidth + 16)
                    height: 30
                    style: strip.style
                    label: ""
                    tone: "toggle"
                    cardFilled: true
                    selected: modelData.address === strip.controls.focusedWorkspaceAddress
                    available: strip.controls.available && !strip.controls.busy
                    tooltip: (special ? "Special workspace " : "Workspace ") + String(modelData.name).replace(/^special:/, "") + " · " + apps.length + (apps.length === 1 ? " window" : " windows")
                    Accessible.name: tooltip
                    onTriggered: strip.controls.focusWorkspace(modelData.address)

                    Row {
                        id: contents
                        anchors.centerIn: parent
                        spacing: 5
                        Text {
                            height: 26
                            verticalAlignment: Text.AlignVCenter
                            text: chip.special ? "$" : String(chip.modelData.name)
                            textFormat: Text.PlainText
                            font.family: strip.style.fontFamily
                            font.pixelSize: strip.style.fontSizeLabel
                            font.weight: chip.selected ? Font.Bold : Font.DemiBold
                            color: chip.selected ? strip.style.accent : strip.style.textSecondary
                            width: Math.min(implicitWidth, 64)
                            elide: Text.ElideRight
                        }
                        Repeater {
                            model: chip.shown
                            Item {
                                required property var modelData
                                width: 15; height: 26
                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: 15
                                    source: strip.searchModel.desktopIconSource(strip.searchModel.desktopEntryFor(modelData))
                                }
                            }
                        }
                        Item {
                            visible: chip.generic > 0
                            width: 13; height: 26
                            StatusIcon {
                                anchors.centerIn: parent
                                width: 13; height: 13
                                kind: "window"
                                ink: strip.style.textMuted
                            }
                        }
                        Text {
                            visible: chip.generic > 1 || (chip.generic > 0 && chip.shown.length > 0)
                            height: 26
                            verticalAlignment: Text.AlignVCenter
                            text: chip.shown.length ? "+" + chip.generic : String(chip.generic)
                            color: strip.style.textMuted
                            font.family: strip.style.fontFamily
                            font.pixelSize: strip.style.fontSizeCaption
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
                    width: 30; height: 30
                    radius: strip.style.radiusControl
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
                        font.family: strip.style.fontFamily
                        font.pixelSize: strip.style.fontSizeSmall
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: trayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
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

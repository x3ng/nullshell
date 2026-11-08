pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import ".."

PopupWindow {
    id: popup

    required property Theme style
    required property var panelWindow
    property bool open: false
    property var owner: null
    property var currentMenu: null
    property var menuStack: []
    property real anchorRight: 0
    property real anchorBottom: 0

    function openFor(trayItem, anchorRightValue, anchorBottomValue) {
        var menuHandle = trayItem?.menu;
        if (!menuHandle) return false;

        dismiss();
        anchorRight = anchorRightValue;
        anchorBottom = anchorBottomValue;
        owner = trayItem;
        menuStack = [menuHandle];
        currentMenu = menuHandle;
        open = true;
        return true;
    }

    function enterSubmenu(entry) {
        if (!entry?.hasChildren) return;
        menuStack = menuStack.concat([entry]);
        currentMenu = entry;
    }

    function leaveSubmenu() {
        if (menuStack.length <= 1) return;
        menuStack = menuStack.slice(0, menuStack.length - 1);
        currentMenu = menuStack[menuStack.length - 1];
    }

    function dismiss() {
        // Clearing QsMenuOpener releases the active entry and emits the
        // matching DBusMenu close event.
        currentMenu = null;
        open = false;
        menuStack = [];
        owner = null;
    }

    function triggerEntry(entry) {
        entry.triggered();
        dismiss();
    }

    function heading() {
        if (menuStack.length > 1 && currentMenu?.text)
            return currentMenu.text.toUpperCase();
        var title = owner?.title || owner?.id || "APPLICATION";
        return title.toUpperCase();
    }

    anchor.window: panelWindow
    visible: open && panelWindow.visible
    implicitWidth: Math.min(280, Math.max(100, panelWindow.width - 16))
    implicitHeight: Math.min(420, Math.max(62, panelWindow.height - 16),
        Math.max(62, menuList.contentHeight + 50))
    anchor.rect.x: Math.round(Math.max(8, Math.min(panelWindow.width - width - 8, anchorRight - width)))
    anchor.rect.y: Math.round(Math.max(8, anchorBottom - height - 6))
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    color: "transparent"
    Region {
        id: trayBlurRegion
        width: popup.width
        height: popup.height
        radius: popup.style.radiusPopup
    }
    BackgroundEffect.blurRegion: popup.visible && popup.style.backdropBlur ? trayBlurRegion : null
    grabFocus: true

    onVisibleChanged: {
        if (visible) style.refreshMaterial();
        if (!visible && open) dismiss();
    }

    QsMenuOpener {
        id: opener
        menu: popup.currentMenu
    }

    MaterialSurface {
        materialTheme: popup.style
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: {
            if (popup.menuStack.length > 1) popup.leaveSubmenu();
            else popup.dismiss();
        }
        radius: popup.style.radiusPopup
        color: Qt.alpha(popup.style.surface, popup.style.glassOpacity)
        border.width: 1
        border.color: popup.style.materialEdge

        Item {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 42

            Item {
                id: backButton
                visible: popup.menuStack.length > 1
                width: visible ? 28 : 0
                height: 28
                anchors.left: parent.left
                anchors.leftMargin: 7
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: popup.style.radiusControl
                    color: backMouse.containsMouse
                        ? popup.style.surfaceHover
                        : "transparent"
                }

                StatusIcon {
                    anchors.centerIn: parent
                    kind: "back"
                    width: 18
                    height: 18
                    ink: popup.style.textSecondary
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: popup.leaveSubmenu()
                }
            }

            Text {
                anchors.left: backButton.right
                anchors.right: closeButton.left
                anchors.leftMargin: backButton.visible ? 4 : 12
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: popup.heading()
                elide: Text.ElideRight
                color: popup.style.textMuted
                font.pixelSize: popup.style.fontSizeMicro
                font.weight: Font.DemiBold
            }

            Item {
                id: closeButton
                width: 28
                height: 28
                anchors.right: parent.right
                anchors.rightMargin: 7
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: popup.style.radiusControl
                    color: closeMouse.containsMouse
                        ? popup.style.surfaceHover
                        : "transparent"
                }

                StatusIcon {
                    anchors.centerIn: parent
                    kind: "close"
                    width: 14
                    height: 14
                    ink: popup.style.textMuted
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: popup.dismiss()
                }
            }
        }

        Rectangle {
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            height: 1
            color: popup.style.separator
        }

        ListView {
            id: menuList
            property var hoveredEntry: null
            spacing: 3
            onModelChanged: hoveredEntry = null
            onContentYChanged: hoveredEntry = null
            anchors.top: header.bottom
            anchors.topMargin: 5
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 5
            anchors.left: parent.left
            anchors.leftMargin: 5
            anchors.right: parent.right
            anchors.rightMargin: 5
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: opener.children ? [...opener.children.values] : []

            delegate: Item {
                id: entry
                required property QsMenuEntry modelData
                readonly property bool checked: modelData.checkState !== Qt.Unchecked
                width: menuList.width
                height: modelData.isSeparator ? 9 : 34
                opacity: modelData.enabled ? 1 : 0.52

                Rectangle {
                    visible: entry.modelData.isSeparator
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: popup.style.spaceSm
                    anchors.rightMargin: popup.style.spaceSm
                    anchors.verticalCenter: parent.verticalCenter
                    height: 1
                    color: popup.style.separator
                }

                Rectangle {
                    visible: !entry.modelData.isSeparator
                    anchors.fill: parent
                    radius: popup.style.radiusControl
                    color: menuList.hoveredEntry === entry && entryMouse.containsMouse && entry.modelData.enabled
                        ? popup.style.surfaceHover
                        : "transparent"
                }

                Item {
                    visible: !entry.modelData.isSeparator
                    width: 18
                    height: 18
                    anchors.left: parent.left
                    anchors.leftMargin: 9
                    anchors.verticalCenter: parent.verticalCenter

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 16
                        source: entry.modelData.icon
                        visible: entry.modelData.buttonType === QsMenuButtonType.None
                            && source !== ""
                            && status !== Image.Error
                    }

                    Rectangle {
                        visible: entry.modelData.buttonType !== QsMenuButtonType.None
                        width: 13
                        height: 13
                        anchors.centerIn: parent
                        radius: entry.modelData.buttonType === QsMenuButtonType.RadioButton
                            ? 7
                            : 3
                        color: entry.checked ? popup.style.accent : "transparent"
                        border.width: 1
                        border.color: entry.checked
                            ? popup.style.accent
                            : popup.style.textMuted

                        Rectangle {
                            visible: entry.checked
                                && entry.modelData.buttonType === QsMenuButtonType.RadioButton
                            width: 5
                            height: 5
                            radius: 3
                            anchors.centerIn: parent
                            color: popup.style.accentInk
                        }

                        StatusIcon {
                            visible: entry.checked
                                && entry.modelData.buttonType === QsMenuButtonType.CheckBox
                            anchors.centerIn: parent
                            kind: entry.modelData.checkState === Qt.PartiallyChecked ? "minus" : "check"
                            width: 12
                            height: 12
                            ink: popup.style.accentInk
                        }
                    }
                }

                Text {
                    visible: !entry.modelData.isSeparator
                    anchors.left: parent.left
                    anchors.leftMargin: 36
                    anchors.right: entryArrow.left
                    anchors.rightMargin: popup.style.spaceSm
                    anchors.verticalCenter: parent.verticalCenter
                    text: entry.modelData.text
                    elide: Text.ElideRight
                    color: popup.style.textPrimary
                    font.pixelSize: popup.style.fontSizeCaption
                    font.weight: Font.Medium
                }

                StatusIcon {
                    id: entryArrow
                    visible: !entry.modelData.isSeparator && entry.modelData.hasChildren
                    width: visible ? 18 : 0
                    height: 18
                    anchors.right: parent.right
                    anchors.rightMargin: popup.style.spaceSm
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "chevron"
                    ink: popup.style.textMuted
                }

                MouseArea {
                    id: entryMouse
                    anchors.fill: parent
                    enabled: !entry.modelData.isSeparator && entry.modelData.enabled
                    hoverEnabled: true
                    onEntered: menuList.hoveredEntry = entry
                    onPositionChanged: menuList.hoveredEntry = entry
                    onExited: {
                        if (menuList.hoveredEntry === entry) menuList.hoveredEntry = null;
                    }
                    onClicked: {
                        if (entry.modelData.hasChildren)
                            popup.enterSubmenu(entry.modelData);
                        else
                            popup.triggerEntry(entry.modelData);
                    }
                }
            }

            Text {
                visible: menuList.count === 0
                anchors.centerIn: parent
                text: "NO ACTIONS"
                color: popup.style.textMuted
                font.pixelSize: popup.style.fontSizeMicro
                font.weight: Font.Medium
            }
        }
    }
}

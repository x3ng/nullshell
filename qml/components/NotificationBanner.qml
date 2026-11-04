pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import ".."

PanelWindow {
    id: banner
    required property var notifs
    required property Theme style
    readonly property int cardWidth: Math.min(400, Math.max(1, width - style.spaceLg * 2))

    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    visible: notifs.popups.length > 0
    color: "transparent"
    anchors { top: true; left: true; right: true }
    margins { top: 10 }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-notifications"
    implicitWidth: 1
    implicitHeight: Math.min(stack.implicitHeight + 1, (screen?.height ?? 900) * 0.75)
    mask: Region { item: viewport }

    Flickable {
        id: viewport
        anchors.horizontalCenter: parent.horizontalCenter
        width: banner.cardWidth
        height: banner.height
        contentWidth: width
        contentHeight: stack.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: stack
            width: viewport.width
            spacing: banner.style.spaceSm
            Repeater {
                model: banner.notifs.popups
                delegate: NotificationCard {
                    id: card
                    required property var modelData
                    readonly property var wrapper: modelData
                    Layout.fillWidth: true
                    style: banner.style
                    entry: wrapper
                    actions: wrapper.actions
                    activationLabel: banner.notifs.activationLabel(wrapper)
                    onHoveredChanged: banner.notifs.setHovered(wrapper, hovered)
                    onActivated: banner.notifs.activateEntry(wrapper)
                    onDismissRequested: banner.notifs.dismiss(wrapper)
                    onActionRequested: action => banner.notifs.invokeAction(wrapper, action)
                    opacity: 0
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Component.onCompleted: opacity = 1
                }
            }
        }
    }
}

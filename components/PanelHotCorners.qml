pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

Scope {
    id: root
    required property var panel
    required property Theme style
    property bool enabled: true
    // Both upper corners open the same panel. Sizes are logical pixels.
    property int dwellTime: 400
    property int cornerSize: 6

    Variants {
        model: Quickshell.screens.reduce((targets, screen) => targets.concat([
            {screen: screen, right: false}, {screen: screen, right: true}
        ]), [])

        PanelWindow {
            id: sensor
            required property var modelData
            property bool armed: false
            property real dwellProgress: 0
            screen: modelData.screen
            visible: root.enabled
            color: "transparent"
            implicitWidth: hint.implicitWidth
            implicitHeight: hint.implicitHeight
            anchors {
                top: true
                left: !sensor.modelData.right
                right: sensor.modelData.right
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell:hot-corner"
            // The visual is larger than the hit area. Only the original corner
            // receives pointer input; the surrounding glow is click-through.
            mask: Region { item: hitArea }

            function updateHover() {
                if (!hover.hovered) {
                    dwell.stop();
                    if (!root.panel.visible && !settle.running) armed = true;
                } else if (armed && !root.panel.visible && root.enabled
                        && hover.point.pressedButtons === Qt.NoButton) {
                    if (!dwell.running) dwell.start();
                } else dwell.stop();
            }

            Component.onCompleted: settle.restart()
            onVisibleChanged: {
                armed = false;
                dwell.stop();
                if (visible) settle.restart();
            }

            HotCornerHint {
                id: hint
                anchors.fill: parent
                style: root.style
                rightCorner: sensor.modelData.right
                progress: sensor.dwellProgress
                opacity: dwell.running ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 100 } }
            }

            Item {
                id: hitArea
                width: root.cornerSize
                height: root.cornerSize
                anchors.top: parent.top
                anchors.left: sensor.modelData.right ? undefined : parent.left
                anchors.right: sensor.modelData.right ? parent.right : undefined

                HoverHandler {
                    id: hover
                    blocking: false
                    onHoveredChanged: sensor.updateHover()
                    onPointChanged: sensor.updateHover()
                }
            }

            NumberAnimation {
                target: sensor
                property: "dwellProgress"
                from: 0
                to: 1
                duration: root.dwellTime
                running: dwell.running
            }

            Timer {
                id: dwell
                interval: root.dwellTime
                onTriggered: {
                    if (!sensor.armed || !hover.hovered || root.panel.visible
                            || !root.enabled || hover.point.pressedButtons !== Qt.NoButton) return;
                    sensor.armed = false;
                    root.panel.openOnScreen(sensor.modelData.screen);
                }
            }

            // The launcher covers the sensor while open. Wait until it has
            // actually unmapped before using hover to rearm, not its fade start.
            // A pointer left in the corner must leave before it can open again.
            Timer {
                id: settle
                interval: 100
                onTriggered: {
                    if (!root.panel.visible && root.enabled)
                        sensor.armed = !hover.hovered;
                }
            }

            Connections {
                target: root.panel
                function onVisibleChanged() {
                    sensor.armed = false;
                    dwell.stop();
                    if (!root.panel.visible) settle.restart();
                    else settle.stop();
                }
            }
        }
    }
}

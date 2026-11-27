pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import ".."

ClippingRectangle {
    id: level
    required property Theme style
    required property var actions
    required property string title
    required property string icon
    required property real value
    property bool available: true
    property bool muted: false
    property string action: ""
    property string detailsAction: ""
    property string detailsTooltip: ""
    signal edited(real value)

    readonly property real clamped: Math.max(0, Math.min(1, value))
    readonly property int trailingWidth: detailsSlot.visible ? 37 : 0
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.minimumWidth: 0
    implicitHeight: 40
    radius: style.radiusCard
    color: style.cardSurface

    // Flush full-bleed tonal fill across the slider body (no nested inner box).
    Item {
        id: trackZone
        anchors.fill: parent
        anchors.rightMargin: level.trailingWidth

        Rectangle {
            width: Math.round(trackZone.width * level.clamped)
            height: trackZone.height
            color: !level.available ? "transparent"
                : level.muted ? level.style.sliderMutedFill : level.style.sliderFill
        }

        Rectangle {
            visible: level.clamped > 0.01 && level.clamped < 0.995 && level.available
            x: Math.max(0, Math.round(trackZone.width * level.clamped) - 1.5)
            width: 1.5
            height: trackZone.height
            color: level.muted ? level.style.outline : level.style.accent
            opacity: 0.7
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            anchors.leftMargin: muteSlot.visible && level.action !== "" ? 38 : 0
            enabled: level.available
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            activeFocusOnTab: level.available
            Accessible.role: Accessible.Slider
            Accessible.name: level.title + ", " + valueLabel.text
            function applyAt(px) {
                const span = Math.max(1, trackZone.width);
                const mapped = px + dragArea.anchors.leftMargin;
                level.edited(Math.max(0, Math.min(1, mapped / span)));
            }
            onPressed: mouse => { dragArea.forceActiveFocus(); applyAt(mouse.x); }
            onPositionChanged: mouse => { if (pressed) applyAt(mouse.x); }
            onWheel: event => {
                const delta = event.angleDelta.y > 0 ? 0.02 : -0.02;
                level.edited(Math.max(0, Math.min(1, level.clamped + delta)));
                event.accepted = true;
            }
            Keys.onLeftPressed: level.edited(Math.max(0, level.clamped - 0.02))
            Keys.onRightPressed: level.edited(Math.min(1, level.clamped + 0.02))
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 0
        spacing: 0

        Item {
            id: muteSlot
            Layout.preferredWidth: 32
            Layout.preferredHeight: 30
            ChoiceButton {
                id: muteButton
                anchors.fill: parent
                visible: level.action !== ""
                style: level.style
                label: ""
                color: muteButton.hovered ? Qt.alpha(level.style.textPrimary, 0.07) : "transparent"
                StatusIcon {
                    anchors.centerIn: parent
                    width: 18; height: 18
                    kind: level.icon
                    muted: level.muted
                    ink: level.muted ? level.style.textMuted : level.style.accent
                }
                tooltip: level.muted ? "Unmute output" : "Mute output"
                available: level.available && level.actions.available(level.action)
                onTriggered: level.actions.execute(level.action)
            }
            StatusIcon {
                anchors.centerIn: parent
                width: 18; height: 18
                visible: level.action === ""
                kind: level.icon
                ink: level.available ? level.style.accent : level.style.textDisabled
            }
        }

        Item { Layout.fillWidth: true; Layout.minimumWidth: 16 }

        Text {
            id: valueLabel
            Layout.rightMargin: 10
            horizontalAlignment: Text.AlignRight
            text: level.available ? Math.round(level.clamped * 100) + "%" : "—"
            color: level.muted ? level.style.textMuted : level.style.textPrimary
            font.family: level.style.fontFamily
            font.pixelSize: level.style.fontSizeLabel
            font.weight: Font.DemiBold
        }

        Rectangle {
            visible: detailsSlot.visible
            Layout.preferredWidth: 1
            Layout.preferredHeight: 20
            color: level.clamped > 0.95 && !level.muted ? Qt.alpha(level.style.textPrimary, 0.12) : level.style.separator
            opacity: 0.8
        }

        Item {
            id: detailsSlot
            visible: level.detailsAction !== ""
            Layout.preferredWidth: 36
            Layout.fillHeight: true
            ChoiceButton {
                id: detailsButton
                anchors.fill: parent
                objectName: level.icon + "-details"
                style: level.style
                color: detailsButton.hovered ? Qt.alpha(level.style.textPrimary, 0.06) : "transparent"
                label: ""
                iconKind: "chevron"
                iconSize: 16
                iconInk: detailsButton.hovered ? level.style.textPrimary : level.style.textMuted
                available: level.detailsAction !== "" && level.actions.available(level.detailsAction)
                tooltip: level.detailsTooltip
                onTriggered: level.actions.execute(level.detailsAction)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: dragArea.activeFocus
        color: "transparent"
        radius: level.radius
        border.width: level.style.focusWidth
        border.color: level.style.focusInk
    }
}

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
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.minimumWidth: 0
    implicitHeight: 42
    radius: style.radiusCard
    color: style.cardSurface

    // Inset pill track inside the card so 0%, 50% and 100% all read unmistakably as a slider.
    ClippingRectangle {
        id: trackZone
        anchors.fill: parent
        anchors.margins: 4
        anchors.rightMargin: detailsSlot.visible ? 39 : 4
        radius: level.style.radiusSmall
        color: level.style.backgroundSurface

        Rectangle {
            width: Math.round(trackZone.width * level.clamped)
            height: trackZone.height
            radius: trackZone.radius
            color: !level.available ? "transparent"
                : level.muted ? level.style.sliderMutedFill : level.style.sliderFill
        }

        Rectangle {
            visible: level.clamped > 0.02 && level.clamped < 0.99 && level.available
            x: Math.max(0, Math.round(trackZone.width * level.clamped) - 2)
            width: 2
            height: trackZone.height
            color: level.muted ? level.style.outline : level.style.accent
            opacity: 0.85
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            anchors.leftMargin: muteSlot.visible && level.action !== "" ? 34 : 0
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
        anchors.leftMargin: 8
        anchors.rightMargin: 6
        spacing: 6

        Item {
            id: muteSlot
            Layout.preferredWidth: 30
            Layout.preferredHeight: 30
            ChoiceButton {
                id: muteButton
                anchors.fill: parent
                visible: level.action !== ""
                style: level.style
                label: ""
                color: muteButton.hovered ? level.style.surfaceHover : "transparent"
                StatusIcon {
                    anchors.centerIn: parent
                    width: 17; height: 17
                    kind: level.icon
                    muted: level.muted
                    ink: level.muted ? level.style.textMuted
                        : muteButton.hovered ? level.style.textPrimary : level.style.accent
                }
                tooltip: level.muted ? "Unmute output" : "Mute output"
                available: level.available && level.actions.available(level.action)
                onTriggered: level.actions.execute(level.action)
            }
            StatusIcon {
                anchors.centerIn: parent
                width: 17; height: 17
                visible: level.action === ""
                kind: level.icon
                ink: level.available ? level.style.accent : level.style.textDisabled
            }
        }

        Item { Layout.fillWidth: true; Layout.minimumWidth: 16 }

        Text {
            id: valueLabel
            Layout.rightMargin: 4
            horizontalAlignment: Text.AlignRight
            text: level.available ? Math.round(level.clamped * 100) + "%" : "—"
            color: level.muted ? level.style.textMuted : level.style.textPrimary
            font.family: level.style.fontFamily
            font.pixelSize: level.style.fontSizeLabel
            font.weight: Font.DemiBold
        }

        Rectangle {
            id: detailsDivider
            visible: detailsSlot.visible
            Layout.preferredWidth: 1
            Layout.preferredHeight: 16
            color: level.style.separator
            opacity: 0.6
        }

        Item {
            id: detailsSlot
            visible: level.detailsAction !== ""
            Layout.preferredWidth: 26
            Layout.preferredHeight: 30
            ChoiceButton {
                id: detailsButton
                anchors.fill: parent
                objectName: level.icon + "-details"
                style: level.style
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

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."

Item {
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
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.minimumWidth: 0
    implicitHeight: 44
    RowLayout {
        anchors.fill: parent
        spacing: level.style.spaceMd
        Item {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 32
            ChoiceButton {
                anchors.fill: parent
                visible: level.action !== ""
                style: level.style
                label: ""
                StatusIcon {
                    anchors.centerIn: parent
                    width: 20; height: 20
                    kind: level.icon
                    muted: level.muted
                    ink: level.muted ? level.style.textMuted : level.style.textSecondary
                }
                tooltip: level.muted ? "Unmute output" : "Mute output"
                available: level.available
                onTriggered: level.actions.execute(level.action)
            }
            StatusIcon {
                anchors.centerIn: parent
                width: 20; height: 20
                visible: level.action === ""
                kind: level.icon
                ink: level.style.textSecondary
            }
        }
        PanelSlider {
            style: level.style
            muted: level.muted
            Layout.fillWidth: true
            implicitHeight: 36
            Layout.minimumWidth: 48
            from: 0; to: 1; stepSize: 0.02
            value: level.value
            enabled: level.available
            activeFocusOnTab: true
            Accessible.name: level.title
            onMoved: level.edited(value)
        }
        Text {
            Layout.preferredWidth: 42
            horizontalAlignment: Text.AlignRight
            text: level.available ? Math.round(level.value * 100) + "%" : "—"
            color: level.muted ? level.style.textMuted : level.style.textSecondary
            font.family: level.style.fontFamily
            font.pixelSize: level.style.fontSizeSmall
        }
        // Reserve the same trailing slot for both levels so tracks and values align.
        Item {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 32
            ChoiceButton {
                anchors.fill: parent
                visible: level.detailsAction !== ""
                objectName: level.icon + "-details"
                style: level.style
                label: ""
                iconKind: "chevron"
                iconSize: 20
                tooltip: level.detailsTooltip
                onTriggered: level.actions.execute(level.detailsAction)
            }
        }

    }
}

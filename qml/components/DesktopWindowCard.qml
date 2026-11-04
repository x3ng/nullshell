pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

GroupCard {
    id: card
    required property var windowData
    required property var controls
    required property var searchModel
    property bool expanded: false
    property string actionMode: ""
    signal expandRequested()
    signal modeRequested(string mode)
    signal focusRequested(string address)
    readonly property var entry: searchModel.desktopEntryFor({appId: windowData.appId})
    readonly property string iconSource: searchModel.desktopIconSource(entry)
    pad: 6
    radius: style.radiusControl
    color: windowMouse.containsMouse ? style.surfaceHover
        : windowData.focused ? style.surfaceSelected : "transparent"

    function showActions() {
        if (!expanded) expandRequested();
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: card.style.spaceSm
        Item {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredHeight: 32
            RowLayout {
                anchors.fill: parent
                spacing: card.style.spaceSm
                Item {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    IconImage {
                        id: icon
                        anchors.fill: parent
                        source: card.iconSource
                        visible: status === Image.Ready
                    }
                    StatusIcon {
                        anchors.fill: parent
                        visible: !icon.visible
                        kind: "window"
                        ink: card.style.textSecondary
                    }
                }
                Column {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 3
                    Text {
                        width: parent.width
                        text: card.windowData.title || card.windowData.appId || "Untitled window"
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: card.style.textPrimary
                        font.family: card.style.fontFamily
                        font.pixelSize: card.style.fontSizeBody
                        font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        text: (card.windowData.appId || "Window")
                            + (card.windowData.focused ? " · Active" : "")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: card.style.textMuted
                        font.family: card.style.fontFamily
                        font.pixelSize: card.style.fontSizeCaption
                    }
                }
            }
            MouseArea {
                id: windowMouse
                objectName: "windowTarget_" + card.windowData.address
                anchors.fill: parent
                enabled: !card.controls.busy
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) card.showActions();
                    else card.focusRequested(card.windowData.address);
                }
            }
        }
        ChoiceButton {
            Layout.preferredWidth: 30
            Layout.minimumWidth: 30
            Layout.preferredHeight: 30
            style: card.style
            label: "⋯"
            textSize: 22
            Accessible.role: Accessible.Button
            Accessible.name: "Window actions"
            Accessible.onPressAction: card.expandRequested()
            selected: card.expanded
            onTriggered: card.expandRequested()
        }
    }

    GridLayout {
        visible: card.expanded
        Layout.fillWidth: true
        columns: card.width >= 416 ? 4 : 2
        columnSpacing: card.style.spaceSm
        rowSpacing: card.style.spaceSm
        ChoiceButton {
            Layout.fillWidth: true
            style: card.style
            label: "Float"
            selected: card.windowData.floating
            available: !card.controls.busy
            onTriggered: card.controls.toggleFloat(card.windowData.address)
        }
        ChoiceButton {
            Layout.fillWidth: true
            style: card.style
            label: "Fullscreen"
            selected: !!card.windowData.fullscreen
            available: !card.controls.busy
            onTriggered: card.controls.toggleFullscreen(card.windowData.address)
        }
        ChoiceButton {
            Layout.fillWidth: true
            style: card.style
            label: "Move"
            selected: card.actionMode === "move"
            available: !card.controls.busy
            onTriggered: card.modeRequested(card.actionMode === "move" ? "" : "move")
        }
        ChoiceButton {
            Layout.fillWidth: true
            style: card.style
            label: "Close"
            selected: card.actionMode === "close"
            available: !card.controls.busy
            onTriggered: card.modeRequested(card.actionMode === "close" ? "" : "close")
        }
    }

    ColumnLayout {
        visible: card.expanded && card.actionMode === "move"
        Layout.fillWidth: true
        Text {
            text: "Move to workspace"
            color: card.style.textSecondary
            font.family: card.style.fontFamily
            font.pixelSize: card.style.fontSizeCaption
        }
        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            spacing: card.style.spaceXs
            Repeater {
                model: card.controls.workspaceTargets.filter(w => w.address !== card.windowData.workspaceAddress)
                ChoiceButton {
                    required property var modelData
                    width: Math.min(120, Math.max(64, implicitWidth))
                    style: card.style
                    label: modelData.name
                    filled: true
                    filledColor: card.style.surfaceHover
                    available: !card.controls.busy
                    onTriggered: {
                        if (card.controls.moveWindow(card.windowData.address, modelData.address)) card.modeRequested("");
                    }
                }
            }
        }
        Text {
            visible: card.controls.workspaceTargets.length < 2
            text: "No other workspace is available."
            color: card.style.textSecondary
            font.family: card.style.fontFamily
            font.pixelSize: card.style.fontSizeCaption
        }
    }

    ColumnLayout {
        visible: card.expanded && card.actionMode === "close"
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: "Close this window?"
            wrapMode: Text.Wrap
            color: card.style.textSecondary
            font.family: card.style.fontFamily
            font.pixelSize: card.style.fontSizeCaption
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: card.style.spaceSm
            ChoiceButton {
                Layout.fillWidth: true
                style: card.style
                label: "Cancel"
                onTriggered: card.modeRequested("")
            }
            ChoiceButton {
                Layout.fillWidth: true
                style: card.style
                label: "Close window"
                tone: "danger"
                filled: true
                filledColor: card.style.surfaceHover
                available: !card.controls.busy
                onTriggered: {
                    if (card.controls.closeWindow(card.windowData.address)) card.modeRequested("");
                }
            }
        }
    }
}

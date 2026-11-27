pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: pane
    required property Theme style
    required property var services
    required property var actions
    readonly property var session: actions.session
    readonly property var system: services.controls
    readonly property var availableProfiles: [
        {id: "power-saver", title: "Saver", icon: "leaf"},
        {id: "balanced", title: "Balanced", icon: "balance"},
        {id: "performance", title: "Performance", icon: "gauge"}
    ].filter(item => (system?.powerProfiles ?? []).includes(item.id))
    property string pendingAction: ""
    readonly property var choices: [
        {id: "lock", title: "Lock screen", icon: "lock"},
        {id: "suspend", title: "Sleep", icon: "moon"},
        {id: "logout", title: "Log out", icon: "logout"},
        {id: "reboot", title: "Restart", icon: "restart"},
        {id: "poweroff", title: "Shut down", icon: "power"}
    ]
    readonly property string pendingTitle: choices.find(choice => choice.id === pendingAction)?.title || ""
    signal closeRequested()
    spacing: 8
    Component.onCompleted: session.refresh()
    onVisibleChanged: if (!visible) pendingAction = ""
    Connections {
        target: pane.session
        function onAccepted(action) { pane.closeRequested(); }
    }

    // Power profile selector (shown when power-profiles-daemon is available).
    GroupCard {
        visible: (pane.system?.powerAvailable ?? false) && pane.availableProfiles.length > 0
        Layout.fillWidth: true
        style: pane.style
        pad: pane.style.spaceSm
        contentSpacing: pane.style.spaceXs

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: pane.availableProfiles
                delegate: ChoiceButton {
                    required property var modelData
                    objectName: "power-profile-" + modelData.id
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 36
                    style: pane.style
                    filled: true
                    tone: "toggle"
                    selected: pane.system?.powerProfile === modelData.id
                    label: modelData.title
                    iconKind: modelData.icon
                    iconSize: 16
                    textSize: pane.style.fontSizeLabel
                    available: pane.actions.available("power:" + modelData.id)
                    onTriggered: pane.actions.execute("power:" + modelData.id)
                }
            }
        }
    }

    GroupCard {
        Layout.fillWidth: true
        style: pane.style
        pad: pane.style.spaceSm
        contentSpacing: 4
        Repeater {
            model: pane.choices
            delegate: ChoiceButton {
                required property var modelData
                objectName: "power-action-" + modelData.id
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                style: pane.style
                label: modelData.title
                iconKind: modelData.icon
                contentAlignment: Qt.AlignLeft
                iconSize: 20
                selected: pane.pendingAction === modelData.id
                available: modelData.id === "lock" ? pane.actions.available("lock") : pane.session.available(modelData.id)
                tooltip: available ? "" : "Unavailable in this session"
                onTriggered: {
                    if (modelData.id === "lock") {
                        if (pane.actions.execute("lock")) pane.closeRequested();
                    } else if (modelData.id === "suspend") {
                        pane.pendingAction = "";
                        pane.session.execute("suspend");
                    } else pane.pendingAction = modelData.id;
                }
            }
        }
    }

    GroupCard {
        visible: pane.pendingAction !== ""
        Layout.fillWidth: true
        style: pane.style
        border.color: pane.style.danger
        Text {
            Layout.fillWidth: true
            text: pane.pendingTitle + "? Save your work before continuing."
            wrapMode: Text.WordWrap
            color: pane.style.textPrimary
            font.family: pane.style.fontFamily
            font.pixelSize: pane.style.fontSizeBody
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ChoiceButton {
                objectName: "power-cancel"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                style: pane.style
                filled: true
                label: "Cancel"
                available: !pane.session.busy
                onTriggered: pane.pendingAction = ""
            }
            ChoiceButton {
                objectName: "power-confirm"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                style: pane.style
                label: pane.pendingTitle
                tone: "danger"
                filled: true
                available: pane.pendingAction !== "" && pane.session.available(pane.pendingAction)
                onTriggered: {
                    if (pane.session.execute(pane.pendingAction)) pane.pendingAction = "";
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: text !== ""
        text: pane.session.busy ? "Waiting for the session…" : pane.session.error
        wrapMode: Text.WordWrap
        color: pane.session.error ? pane.style.danger : pane.style.textMuted
        font.family: pane.style.fontFamily
        font.pixelSize: pane.style.fontSizeSmall
    }
}

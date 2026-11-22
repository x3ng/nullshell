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
    property string pendingAction: ""
    readonly property var choices: [
        {id: "lock", title: "Lock screen", icon: "lock"},
        {id: "suspend", title: "Sleep", icon: "moon"},
        {id: "logout", title: "Log out", icon: "back"},
        {id: "reboot", title: "Restart", icon: "power"},
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
            filled: true
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
    ColumnLayout {
        visible: pane.pendingAction !== ""
        Layout.fillWidth: true
        spacing: pane.style.spaceMd
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
    ChoiceButton {
        objectName: "power-idle-settings"
        Layout.fillWidth: true
        visible: pane.pendingAction === "" && pane.actions.available("idle")
        style: pane.style
        label: "Idle and sleep settings"
        iconKind: "clock"
        contentAlignment: Qt.AlignLeft
        onTriggered: pane.actions.execute("idle")
    }
    RowLayout {
        Layout.fillWidth: true
        visible: pane.pendingAction === ""
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: pane.services.keepAwakeUntil > 0
                ? "Keep awake until " + Qt.formatTime(new Date(pane.services.keepAwakeUntil), "hh:mm")
                : "Keep awake for"
            color: pane.style.textSecondary
            font.family: pane.style.fontFamily
            font.pixelSize: pane.style.fontSizeBody
        }
        ConnectionField {
            id: duration
            objectName: "awake-duration"
            style: pane.style
            Layout.preferredWidth: 88
            visible: !pane.services.keepAwakeUntil
            placeholderText: "Minutes"
            validator: IntValidator { bottom: 1; top: 1440 }
            onAccepted: if (acceptableInput) pane.services.keepAwakeFor(Number(text))
        }
        ChoiceButton {
            objectName: "awake-duration-apply"
            Layout.preferredWidth: 88
            Layout.preferredHeight: 40
            style: pane.style
            label: pane.services.keepAwakeUntil ? "End timer" : "Start"
            available: pane.services.keepAwakeReady && (pane.services.keepAwakeUntil > 0 || duration.acceptableInput)
            onTriggered: pane.services.keepAwakeFor(pane.services.keepAwakeUntil ? 0 : Number(duration.text))
        }
    }

}

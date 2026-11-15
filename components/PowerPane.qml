pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: pane
    required property Theme style
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
            Layout.preferredHeight: 42
            style: pane.style
            label: modelData.title
            iconKind: modelData.icon
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
        spacing: 10
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
}

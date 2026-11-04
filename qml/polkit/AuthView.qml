import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

MaterialSurface {
    id: root
    materialTheme: theme
    required property var theme
    required property var flow
    implicitHeight: form.implicitHeight + 48
    radius: theme.radiusPanel
    color: Qt.alpha(theme.panelSurface, theme.glassOpacity)
    border.color: theme.materialEdge
    border.width: 1
    signal cancelled()
    readonly property bool waiting: !!flow && flow.isResponseRequired && !flow.isCompleted

    function resetInput() {
        secret.clear();
        if (waiting) Qt.callLater(() => secret.forceActiveFocus());
    }
    function submit() {
        if (!waiting) return;
        const answer = secret.text;
        secret.clear();
        flow.submit(answer);
    }
    function cancel() {
        secret.clear();
        if (flow && !flow.isCompleted) flow.cancelAuthenticationRequest();
        cancelled();
    }
    onFlowChanged: resetInput()
    onWaitingChanged: resetInput()
    Keys.onEscapePressed: cancel()

    component Label: Text {
        Layout.fillWidth: true
        font.family: root.theme.fontFamily
        font.pixelSize: 14
        color: root.theme.textPrimary
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    component Action: Button {
        property bool primary: false
        implicitHeight: 42
        font.family: root.theme.fontFamily
        font.pixelSize: 14
        contentItem: Text {
            text: parent.text
            font: parent.font
            color: parent.primary ? root.theme.accentInk : root.theme.textPrimary
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: root.theme.radiusInput
            color: parent.primary ? root.theme.accent : root.theme.surfaceRaised
            opacity: parent.enabled ? (parent.down ? 0.75 : 1) : 0.45
            border.width: parent.activeFocus ? 1 : 0
            border.color: root.theme.accent
        }
    }

    ColumnLayout {
        id: form
        x: 24; y: 24
        width: parent.width - 48
        spacing: 16
        Label { text: "Authentication required"; font.pixelSize: 22; font.weight: Font.Medium }
        Label { text: root.flow?.message || ""; color: root.theme.textSecondary }
        Label {
            text: root.flow?.selectedIdentity ? "Authenticate as " + root.flow.selectedIdentity.displayName : ""
            visible: text.length > 0 && (root.flow?.identities.length || 0) <= 1
            font.pixelSize: 13
            color: root.theme.textMuted
        }
        ComboBox {
            id: identities
            Layout.fillWidth: true
            implicitHeight: 42
            visible: count > 1
            model: root.flow?.identities || []
            textRole: "displayName"
            currentIndex: root.flow ? root.flow.identities.indexOf(root.flow.selectedIdentity) : -1
            onActivated: index => {
                secret.clear();
                if (root.flow) root.flow.selectedIdentity = root.flow.identities[index];
            }
            font.family: root.theme.fontFamily
            palette.text: root.theme.textPrimary
            palette.buttonText: root.theme.textPrimary
            palette.window: root.theme.surfaceRaised
            palette.base: root.theme.surfaceRaised
            palette.highlight: root.theme.surfaceSelected
            background: Rectangle { radius: root.theme.radiusInput; color: root.theme.surfaceRaised }
        }
        Label {
            text: root.flow?.inputPrompt || "Password"
            visible: root.waiting
            font.pixelSize: 13
            color: root.theme.textSecondary
        }
        TextField {
            id: secret
            Layout.fillWidth: true
            implicitHeight: 48
            enabled: root.waiting
            echoMode: root.flow?.responseVisible ? TextInput.Normal : TextInput.Password
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData
            selectByMouse: true
            color: root.theme.textPrimary
            font.family: root.theme.fontFamily
            font.pixelSize: 15
            leftPadding: 14
            rightPadding: 14
            background: Rectangle {
                radius: root.theme.radiusInput
                color: root.theme.inputSurface
                border.width: 1
                border.color: secret.activeFocus ? root.theme.accent : root.theme.separator
            }
            onAccepted: root.submit()
        }
        Label {
            text: root.flow?.supplementaryMessage || (root.flow?.failed ? "Authentication failed. Try again." : "")
            visible: text.length > 0
            color: root.flow?.supplementaryIsError || root.flow?.failed ? root.theme.danger : root.theme.textSecondary
            font.pixelSize: 13
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Action { text: "Cancel"; Layout.fillWidth: true; onClicked: root.cancel() }
            Action {
                text: root.waiting ? "Authenticate" : "Authenticating…"
                primary: true
                enabled: root.waiting
                Layout.fillWidth: true
                onClicked: root.submit()
            }
        }
    }
    Connections {
        target: root.flow
        function onSelectedIdentityChanged() { root.resetInput(); }
        function onIsCompletedChanged() { root.resetInput(); }
    }
}

import QtQuick
import QtQuick.Window
import Quickshell

ShellRoot {
    Theme { id: style; darkMode: Quickshell.env("QS_PREVIEW_LIGHT") !== "1" }
    QtObject {
        id: mock
        property string message: "Authentication is required to manage system services."
        property var identities: [{displayName: "Preview user"}, {displayName: "Administrator"}]
        property var selectedIdentity: identities[0]
        property bool isResponseRequired: true
        property bool isCompleted: false
        property bool responseVisible: false
        property string inputPrompt: "Password"
        property string supplementaryMessage: ""
        property bool supplementaryIsError: false
        property bool failed: false
        function submit(answer) { failed = true; }
        function cancelAuthenticationRequest() { Qt.quit(); }
    }
    FloatingWindow {
        id: window
        implicitWidth: 480
        implicitHeight: view.implicitHeight
        visible: true
        title: "Quickshell · Authentication preview"
        color: style.panelSurface
        AuthView {
            id: view
            anchors.fill: parent
            theme: style
            flow: mock
        }
    }
}

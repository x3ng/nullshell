import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Services.Greetd

ShellRoot {
    id: root
    readonly property var style: loginTheme
    property bool busy: false
    property bool awaitingReply: false
    property string pendingSecret: ""
    property bool hasPendingSecret: false
    property string status: Greetd.available ? "" : "greetd is unavailable"

    function submit(user, secret) {
        if (busy) return;
        if (!user) {
            status = "Enter a user name";
            return;
        }
        if (!Greetd.available) {
            status = "greetd is unavailable";
            return;
        }
        if (!catalog.current) {
            status = "No Wayland session is available";
            return;
        }
        if (awaitingReply) {
            awaitingReply = false;
            busy = true;
            Greetd.respond(secret);
            loginView.clearSecret();
            return;
        }
        if (Greetd.state !== GreetdState.Inactive) return;
        pendingSecret = secret;
        hasPendingSecret = true;
        busy = true;
        status = "";
        Greetd.createSession(user);
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            root.status = message || (error ? "Authentication error" : "");
            if (!responseRequired) return;
            if (root.hasPendingSecret && !echoResponse) {
                const answer = root.pendingSecret;
                root.pendingSecret = "";
                root.hasPendingSecret = false;
                Greetd.respond(answer);
                loginView.clearSecret();
            } else {
                root.pendingSecret = "";
                root.hasPendingSecret = false;
                root.busy = false;
                root.awaitingReply = true;
                loginView.focusInput();
            }
        }
        function onAuthFailure(message) {
            root.busy = false;
            root.awaitingReply = false;
            root.pendingSecret = "";
            root.hasPendingSecret = false;
            root.status = message || "Authentication failed";
            loginView.clearSecret();
            loginView.focusInput();
        }
        function onReadyToLaunch() {
            const session = catalog.current;
            if (!session) {
                root.busy = false;
                root.status = "Selected session is unavailable";
                Greetd.cancelSession();
                return;
            }
            root.status = "Starting " + session.name + "…";
            const environment = ["XDG_SESSION_TYPE=wayland"];
            if (session.desktopNames) {
                const name = session.desktopNames.replace(/;$/, "").replace(/;/g, ":");
                environment.push("XDG_CURRENT_DESKTOP=" + name);
                environment.push("XDG_SESSION_DESKTOP=" + name);
            }
            Greetd.launch(session.args, environment);
        }
        function onError(error) {
            root.busy = false;
            root.awaitingReply = false;
            root.pendingSecret = "";
            root.hasPendingSecret = false;
            root.status = error;
        }
    }

    Theme { id: loginTheme; darkMode: true }
    SessionCatalog { id: catalog }

    Window {
        id: window
        visible: true
        width: 1280
        height: 800
        color: root.style.panelSurface
        title: "Login"
        onVisibleChanged: if (visible) Qt.callLater(loginView.focusInput)

        LoginView {
            id: loginView
            anchors.fill: parent
            theme: root.style
            userName: ""
            editableUser: true
            sessions: catalog.sessions
            selectedSessionId: catalog.selectedId
            message: root.status
            busy: root.busy
            showPowerActions: true
            onSelectSession: id => catalog.choose(id)
            onPowerRequested: action => Quickshell.execDetached(["systemctl", action])
            onSubmit: (userName, secret) => root.submit(userName, secret)
        }

    }
}

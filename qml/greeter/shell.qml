import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

ShellRoot {
    id: root
    readonly property var style: loginTheme
    property bool busy: false
    property bool awaitingReply: false
    property string pendingSecret: ""
    property bool hasPendingSecret: false
    property string rememberedUser: ""
    property string authenticatedUser: ""
    property var pendingLaunch: null
    property string status: Greetd.available ? "" : "greetd is unavailable"
    readonly property string statePath: Quickshell.env("NULLSHELL_GREETER_STATE_FILE")
        || ((Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
            + "/nullshell/greeter-login.json")

    function launchPending() {
        if (!pendingLaunch) return;
        const request = pendingLaunch;
        pendingLaunch = null;
        Greetd.launch(request.args, request.environment);
    }

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
        authenticatedUser = user;
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
            root.authenticatedUser = "";
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
            root.pendingLaunch = {args: session.args, environment: environment};
            const contents = JSON.stringify({version: 1, user: root.authenticatedUser,
                session: session.id}) + "\n";
            if (loginState.text() === contents) root.launchPending();
            else loginState.setText(contents);
        }
        function onError(error) {
            root.busy = false;
            root.awaitingReply = false;
            root.pendingSecret = "";
            root.hasPendingSecret = false;
            root.authenticatedUser = "";
            root.status = error;
        }
    }

    Theme { id: loginTheme; darkMode: true }
    SessionCatalog { id: catalog }
    FileView {
        id: loginState
        path: root.statePath
        preload: true
        blockLoading: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                if (saved.version !== 1 || typeof saved.user !== "string"
                    || typeof saved.session !== "string") return;
                if (saved.user.length <= 128 && !/[\x00-\x1f\x7f]/.test(saved.user))
                    root.rememberedUser = saved.user;
                if (/^[^/\x00-\x1f\x7f]+\.desktop$/.test(saved.session))
                    catalog.preferredId = saved.session;
            } catch (_) { /* Invalid state uses portable defaults. */ }
        }
        onSaved: root.launchPending()
        onSaveFailed: {
            console.warn("Could not save greeter login choice");
            root.launchPending();
        }
    }

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
            userName: root.rememberedUser
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

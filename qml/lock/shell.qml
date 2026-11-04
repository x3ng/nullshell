import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland

ShellRoot {
    id: root
    // A reload must never reset an active lock to the daemon's unlocked default.
    Component.onCompleted: Quickshell.watchFiles = false
    property bool busy: false
    property bool awaitingReply: false
    property bool hasPendingSecret: false
    property string pendingSecret: ""
    property string status: ""
    readonly property var style: loginTheme
    signal clearInput()

    function submit(userName, secret) {
        if (busy) return;
        if (awaitingReply) {
            awaitingReply = false;
            busy = true;
            pam.respond(secret);
            clearInput();
            return;
        }
        pendingSecret = secret;
        hasPendingSecret = true;
        busy = true;
        status = "";
        if (!pam.start()) {
            busy = false;
            hasPendingSecret = false;
            pendingSecret = "";
            status = "Could not start authentication";
        }
    }

    WallpaperState { id: wallpaperState; synchronous: true }

    // Hold decoded images in Qt's process-local cache before a lock request.
    // Native size avoids a second decode when lock-surface geometry arrives.
    Variants {
        model: Quickshell.screens
        delegate: Image {
            required property var modelData
            source: wallpaperState.urlFor(wallpaperState.entryFor(modelData.name).path)
            asynchronous: true
            cache: true
            visible: false
            fillMode: wallpaperState.entryFor(modelData.name).fit === "contain" ? Image.PreserveAspectFit
                : wallpaperState.entryFor(modelData.name).fit === "stretch" ? Image.Stretch : Image.PreserveAspectCrop
        }
    }

    Theme { id: loginTheme; darkMode: appearance.text().trim() !== "light" }
    FileView {
        id: appearance
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell/appearance-mode"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    IpcHandler {
        target: "locker"
        function lock(): string {
            if (!locker.locked) {
                root.status = "";
                root.clearInput();
                locker.locked = true;
            }
            return locker.locked ? "locked" : "failed";
        }
        function status(): string {
            return JSON.stringify({locked: locker.locked, secure: locker.secure});
        }
    }

    PamContext {
        id: pam
        config: "quickshell-lock"
        user: Quickshell.env("USER")

        onPamMessage: {
            root.status = message;
            if (!responseRequired) return;
            if (root.hasPendingSecret && !responseVisible) {
                const answer = root.pendingSecret;
                root.pendingSecret = "";
                root.hasPendingSecret = false;
                respond(answer);
                root.clearInput();
            } else {
                root.pendingSecret = "";
                root.hasPendingSecret = false;
                root.busy = false;
                root.awaitingReply = true;
            }
        }
        onCompleted: result => {
            root.busy = false;
            root.awaitingReply = false;
            root.pendingSecret = "";
            root.hasPendingSecret = false;
            root.clearInput();
            if (result === PamResult.Success) {
                locker.locked = false;
                root.status = "";
            } else {
                root.status = "Authentication failed";
            }
        }
        onError: error => {
            root.busy = false;
            root.pendingSecret = "";
            root.hasPendingSecret = false;
            root.clearInput();
            root.status = "Authentication error";
        }
    }

    WlSessionLock {
        id: locker
        locked: false

        WlSessionLockSurface {
            id: lockSurface
            color: loginTheme.panelSurface

            WallpaperImage {
                anchors.fill: parent
                source: lockSurface.screen
                    ? wallpaperState.urlFor(wallpaperState.entryFor(lockSurface.screen.name).path) : ""
                asynchronous: false
                nativeSize: true
                cacheImage: true
                layer.enabled: true
                layer.effect: MultiEffect {
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blur: 1
                    blurMax: 48
                }
                fit: wallpaperState.entryFor(lockSurface.screen ? lockSurface.screen.name : "").fit
                fallbackColor: loginTheme.panelSurface
            }
            Rectangle { anchors.fill: parent; color: loginTheme.wallpaperScrim }

            LoginView {
                id: loginView
                anchors.fill: parent
                theme: root.style
                transparentBackground: true
                cardOpacity: loginTheme.frostedOpacity
                frosted: true
                userName: Quickshell.env("USER")
                message: root.status
                busy: root.busy
                onSubmit: (userName, secret) => root.submit(userName, secret)
                Component.onCompleted: Qt.callLater(focusInput)
                Connections {
                    target: root
                    function onClearInput() {
                        loginView.clearSecret();
                        loginView.focusInput();
                    }
                }
            }
        }
    }
}

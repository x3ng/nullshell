import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
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
    property string selectedScreenName: ""
    readonly property bool hyprland: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== ""
    readonly property string primaryScreenName: {
        if (selectedScreenName && Quickshell.screens.some(s => s.name === selectedScreenName))
            return selectedScreenName;
        const focused = hyprland ? (Hyprland.focusedMonitor?.name ?? "") : "";
        if (focused && Quickshell.screens.some(s => s.name === focused))
            return focused;
        return Quickshell.screens[0]?.name ?? "";
    }
    readonly property var style: loginTheme
    signal clearInput()

    function submit(userName, secret) {
        if (busy) return;
        if (awaitingReply) {
            if (!secret.length) return;
            awaitingReply = false;
            busy = true;
            pam.respond(secret);
            clearInput();
            return;
        }
        // Only queue a secret when non-empty so PAM modules like fprintd/u2f can
        // prompt without immediately feeding an empty password to pam_unix.
        pendingSecret = secret;
        hasPendingSecret = secret.length > 0;
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
    LoginInfo { id: loginInfo; active: locker.locked }
    SystemClock { id: secondaryClock; precision: SystemClock.Minutes; enabled: locker.locked && Quickshell.screens.length > 1 }

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
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/nullshell/appearance-mode"
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
                root.selectedScreenName = "";
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
        config: "nullshell-lock"
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
                root.selectedScreenName = "";
                root.status = "";
            } else {
                root.status = "Authentication failed";
            }
        }
        onError: error => {
            root.busy = false;
            root.awaitingReply = false;
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
            readonly property bool primarySurface: !lockSurface.screen
                || Quickshell.screens.length <= 1
                || lockSurface.screen.name === root.primaryScreenName
            color: loginTheme.panelSurface
            onPrimarySurfaceChanged: if (primarySurface) Qt.callLater(loginView.focusInput)

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

            // Secondary monitors display calm time/date and bring the auth card over on click.
            Item {
                anchors.fill: parent
                visible: !lockSurface.primarySurface

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    opacity: 0.88

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(secondaryClock.date, "HH:mm")
                        color: loginTheme.textPrimary
                        font.family: loginTheme.fontFamily
                        font.pixelSize: 44
                        font.weight: Font.Bold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(secondaryClock.date, "dddd, MMMM d")
                        color: loginTheme.textSecondary
                        font.family: loginTheme.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        if (lockSurface.screen) root.selectedScreenName = lockSurface.screen.name;
                    }
                }
            }

            LoginView {
                id: loginView
                anchors.fill: parent
                visible: lockSurface.primarySurface
                theme: root.style
                transparentBackground: true
                cardOpacity: loginTheme.frostedOpacity
                frosted: true
                userName: Quickshell.env("USER")
                message: root.status
                busy: root.busy
                batteryText: loginInfo.batteryText
                batteryLow: loginInfo.batteryLow
                keyboardLayout: loginInfo.keyboardLayout
                capsLock: loginInfo.capsLock
                onKeyboardStatusRequested: loginInfo.refreshKeyboard()
                onDismissMessageRequested: if (!root.busy) root.status = ""
                onSubmit: (userName, secret) => root.submit(userName, secret)
                Component.onCompleted: if (lockSurface.primarySurface) Qt.callLater(focusInput)
                Connections {
                    target: root
                    function onClearInput() {
                        loginView.clearSecret();
                        if (lockSurface.primarySurface) loginView.focusInput();
                    }
                }
            }
        }
    }
}

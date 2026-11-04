import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import Quickshell.Io

ShellRoot {
    id: preview
    property bool lockMode: Quickshell.env("QS_PREVIEW_LOCK") === "1"
    property bool lightMode: Quickshell.env("QS_PREVIEW_LIGHT") === "1"
    IpcHandler {
        target: "preview"
        function mode(lock: bool): void {
            preview.lockMode = lock;
            loginView.powerMenuOpen = false;
            loginView.sessionPickerOpen = false;
            loginView.clearSecret();
            loginView.focusInput();
        }
        function power(open: bool): void { loginView.powerMenuOpen = open; }
        function sessions(open: bool): void { loginView.sessionPickerOpen = open; }
        function feedback(message: string, busy: bool): void {
            loginView.message = message;
            loginView.busy = busy;
        }
        function light(enabled: bool): void { preview.lightMode = enabled; }
    }
    Theme { id: loginTheme; darkMode: !preview.lightMode }
    WallpaperState { id: wallpaperState }
    SessionCatalog { id: catalog }

    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 1100
        implicitHeight: 720
        title: preview.lockMode
            ? "Quickshell · Lock screen preview" : "Quickshell · Greeter preview"
        color: preview.lockMode ? loginTheme.panelSurface : loginTheme.backgroundSurface
        onVisibleChanged: if (visible) Qt.callLater(loginView.focusInput)

        WallpaperImage {
            anchors.fill: parent
            layer.enabled: preview.lockMode
            layer.effect: MultiEffect {
                autoPaddingEnabled: false
                blurEnabled: true
                blur: 1
                blurMax: 48
            }
            visible: preview.lockMode
            source: wallpaperState.urlFor(wallpaperState.entryFor(Quickshell.screens[0]?.name || "").path)
            fit: wallpaperState.entryFor(Quickshell.screens[0]?.name || "").fit
        }
        Rectangle {
            anchors.fill: parent
            visible: preview.lockMode
            color: loginTheme.wallpaperScrim
        }
        LoginView {
            id: loginView
            anchors.fill: parent
            theme: loginTheme
            transparentBackground: preview.lockMode
            cardOpacity: preview.lockMode ? loginTheme.frostedOpacity : 1
            frosted: preview.lockMode
            userName: Quickshell.env("USER")
            editableUser: !preview.lockMode
            sessions: preview.lockMode ? [] : catalog.sessions
            selectedSessionId: catalog.selectedId
            showPowerActions: !preview.lockMode
            powerMenuOpen: Quickshell.env("QS_PREVIEW_POWER_OPEN") === "1"
            onSelectSession: id => catalog.choose(id)
            onPowerRequested: action => Qt.quit()
            onSubmit: (userName, secret) => Qt.quit()
        }
    }
}

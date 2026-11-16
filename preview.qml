import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import Quickshell.Io

ShellRoot {
    id: preview
    property bool lockMode: Quickshell.env("QS_PREVIEW_LOCK") === "1"
    property bool lightMode: Quickshell.env("QS_PREVIEW_LIGHT") === "1"
    property string infoScenario: "normal"
    property int keyboardRefreshes: 0
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
        function info(scenario: string): void { preview.infoScenario = scenario; }
        function capture(path: string): bool { return loginView.grabToImage(result => result.saveToFile(path)); }
        function infoStatus(): string {
            return JSON.stringify({battery: loginView.batteryText, low: loginView.batteryLow,
                keyboard: loginView.keyboardLayout, caps: loginView.capsLock, lock: preview.lockMode,
                width: loginView.width, height: loginView.height, keyboardRefreshes: preview.keyboardRefreshes});
        }
        function appearanceStatus(): string {
            return JSON.stringify({valid: appearance.valid, dark: loginTheme.darkMode,
                background: String(loginTheme.backgroundSurface), accent: String(loginTheme.accent), error: appearance.error, wallpaperReady: greeterBackground.ready, wallpaperError: greeterBackground.error});
        }
        function size(width: int, height: int): void {
            window.minimumSize = Qt.size(width, height);
            window.maximumSize = Qt.size(width, height);
            window.implicitWidth = width;
            window.implicitHeight = height;
        }
        function quit(): void { Qt.quit(); }
    }
    AppearanceSnapshot {
        id: appearance
        path: Quickshell.env("NULLSHELL_APPEARANCE_FILE")
    }
    Theme {
        id: loginTheme
        darkMode: appearance.valid ? appearance.darkMode : !preview.lightMode
        colors: appearance.colors
    }
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
        GreeterWallpaper {
            id: greeterBackground
            anchors.fill: parent
            visible: !preview.lockMode
            fallbackColor: loginTheme.backgroundSurface
        }
        Rectangle {
            anchors.fill: parent
            visible: !preview.lockMode && greeterBackground.ready
            color: loginTheme.wallpaperScrim
        }
        LoginView {
            id: loginView
            anchors.fill: parent
            theme: loginTheme
            transparentBackground: true
            cardOpacity: preview.lockMode ? loginTheme.frostedOpacity : 1
            frosted: preview.lockMode
            userName: "preview"
            batteryText: preview.infoScenario === "missing" ? ""
                : preview.infoScenario === "low" ? "Battery 12%"
                : preview.infoScenario === "full" ? "Battery 100% · Fully charged" : "Battery 76% · Charging"
            batteryLow: preview.infoScenario === "low"
            keyboardLayout: preview.infoScenario === "missing" || preview.infoScenario === "cage" ? ""
                : preview.infoScenario === "long" ? "English (US, international, with dead keys)" : "English (US)"
            capsLock: preview.infoScenario === "low" || preview.infoScenario === "long"
            onKeyboardStatusRequested: preview.keyboardRefreshes++
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

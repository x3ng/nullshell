//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "components"

ShellRoot {
    AppearanceState { id: appearance }
    Theme { id: theme; darkMode: appearance.darkMode }
    DesktopServices {
        id: desktop
        controlsVisible: launcher.open
        wifiDiscoveryActive: launcher.open && launcher.showingDetails && launcher.controlSection === "wifi"
        terminalCommand: desktopSearch.terminalCommand
        onFeedback: (key, summary, body, critical) =>
            notifications.notifyLocal(key, {summary: summary, body: body, critical: critical})
    }
    WallpaperState { id: wallpaperState }
    WallpaperWindows { wallpaper: wallpaperState }
    WallpaperPicker { id: wallpaperPicker; wallpaper: wallpaperState; style: theme }
    IdlePolicy { keepAwake: desktop.keepAwake; ready: desktop.keepAwakeReady }
    DesktopSearch { id: desktopSearch; query: launcher.query; actions: shellActions }
    Notifications { id: notifications }
    BatteryAlerts { battery: desktop.battery; notifications: notifications }
    ScreenKeyboard {
        id: keyboard
        style: theme
        onFeedback: (key, summary, body, critical) =>
            notifications.notifyLocal(key, {summary: summary, body: body, critical: critical})
    }
    WorkspaceLayoutState { id: workspaceLayouts }
    HyprlandControls {
        id: hyprControls
        layoutState: workspaceLayouts
        onFeedback: (key, summary, body, critical) =>
            notifications.notifyLocal(key, {summary: summary, body: body, critical: critical})
    }
    ShellActions {
        id: shellActions
        services: desktop
        appearance: appearance
        keyboard: keyboard
        hyprControls: hyprControls
        onNavigateRequested: section => launcher.navigate(section)
        onWallpaperRequested: { launcher.dismiss(); wallpaperPicker.showPicker(); }
    }

    Connections {
        target: desktop.controls
        function onFeedback(key, summary, body, critical) {
            notifications.notifyLocal(key, {summary: summary, body: body, critical: critical});
        }
    }

    // Darkman owns the appearance preference; the shell mirrors it locally.
    // Pages fit their content under one height limit; details own their header.
    LauncherPanel {
        id: launcher
        onOpenChanged: { if (open) workspaceLayouts.refresh(); }
        services: desktop
        style: theme
        appearance: appearance
        searchModel: desktopSearch
        notifs: notifications
        keyboard: keyboard
        hyprControls: hyprControls
        actions: shellActions
    }
    PanelHotCorners { panel: launcher; style: theme }
    NotificationBanner { notifs: notifications; style: theme }
    OsdOverlay { shell: desktop; style: theme; searchModel: desktopSearch; layoutState: workspaceLayouts; controls: hyprControls }

    IpcHandler {
        target: "idle"
        function setKeepAwake(enabled: bool): bool { return desktop.setKeepAwake(enabled); }
        function status(): string {
            return JSON.stringify({ready: desktop.keepAwakeReady, keepAwake: desktop.keepAwake,
                inhibitorActive: desktop.keepAwakeInhibitorActive});
        }
    }

    IpcHandler {
        target: "wallpaper"
        function showPicker(): void { launcher.dismiss(); wallpaperPicker.showPicker(); }
        function status(): string {
            return JSON.stringify({loaded: wallpaperState.loaded, error: wallpaperState.error,
                screens: Quickshell.screens.map(screen => ({name: screen.name, wallpaper: wallpaperState.entryFor(screen.name)}))});
        }
    }

    IpcHandler {
        target: "appearance"
        function setMode(mode: string): void {
            if (mode === "dark" || mode === "light") appearance.setTheme(mode === "dark");
        }
        function status(): string {
            return JSON.stringify({mode: appearance.darkMode ? "dark" : "light",
                ready: appearance.appearanceKnown, available: appearance.appearanceAvailable,
                error: appearance.appearanceError});
        }
    }

    IpcHandler {
        target: "launcher"
        function search(query: string): void { launcher.openSearch(query); }
        function toggle(): void { launcher.toggle(); }
        function close(): void { launcher.dismiss(); }
    }
}

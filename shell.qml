//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Io
import "components"

ShellRoot {
    // Ensure the user state directory stays private (0700) even on fresh installs without migrate-state.
    Process {
        command: ["install", "-d", "-m", "0700",
            (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/nullshell"]
        running: true
    }
    ShellConfig {
        id: config
        onRejected: reason => notifications.notifyLocal("configuration", {
            summary: "Could not load configuration", body: reason, critical: false
        })
    }
    AppearanceState { id: appearance; settings: config.values.appearance }
    DesktopTheme { id: theme; darkMode: appearance.darkMode }
    AppearanceExport {
        id: appearanceExport
        theme: theme
        ready: appearance.appearanceKnown
    }
    DesktopServices {
        id: desktop
        mixerVisible: launcher.mixerVisible
        controlsVisible: launcher.open || launcher.detachedControls
        wifiDiscoveryActive: launcher.detachedWifi || (launcher.open && launcher.showingDetails && launcher.controlSection === "wifi")
        onFeedback: (key, summary, body, critical) =>
            notifications.notifyLocal(key, {summary: summary, body: body, critical: critical})
    }
    DisplayProfiles {
        id: displayProfiles
        mode: config.ready ? config.values.displays.mode : "off"
        onEditorTrialReady: {
            if (!launcher.detailPages.isDetached("displays")) {
                launcher.openOnScreen(launcher.preferredScreen);
                launcher.navigate("displays");
            }
        }
    }
    WallpaperState { id: wallpaperState }
    WallpaperExport { id: wallpaperExport; wallpaper: wallpaperState }
    WallpaperWindows { wallpaper: wallpaperState }
    IdlePreferences { id: idlePreferences; configured: config.values.idle }
    IdlePolicy {
        keepAwake: desktop.keepAwake
        ready: desktop.keepAwakeReady && config.ready && idlePreferences.ready
        deadlines: idlePreferences.values
        onLockRequested: shellActions.session.lock()
    }
    DesktopSearch {
        id: desktopSearch
        query: launcher.query
        actions: shellActions
        terminalCommand: config.values.terminal
        aliases: config.values.search.aliases
        onFeedback: (key, summary, body, critical) =>
            notifications.notifyLocal(key, {summary: summary, body: body, critical: critical})
    }
    Notifications {
        id: notifications
        settings: config.values.notifications
        settingsReady: config.ready
    }
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
    RegionCapture {
        id: capture
        panelVisible: launcher.visible
        onHidePanel: launcher.dismiss()
        onFailed: reason => notifications.notifyLocal("screenshot-error", {summary: "Screenshot failed", body: reason})
    }
    ShellActions {
        id: shellActions
        services: desktop
        appearance: appearance
        displaysAvailable: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
        keyboard: keyboard
        notifs: notifications
        captureBusy: capture.pending
        onCaptureRequested: capture.request()
        onNavigateRequested: section => launcher.navigate(section)
    }

    Connections {
        target: shellActions.session
        function onLockFailed(reason) {
            notifications.notifyLocal("session-lock", {summary: "Could not lock the screen", body: reason, critical: true});
        }
    }
    Connections {
        target: desktop.controls
        function onFeedback(key, summary, body, critical) {
            notifications.notifyLocal(key, {summary: summary, body: body, critical: critical});
        }
    }

    // The shell owns the persistent effective appearance preference.
    // Pages fit their content under one height limit; details own their header.
    SystemClock { id: panelClock; precision: SystemClock.Minutes }
    LauncherPanel {
        id: launcher
        preferredScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        trayItems: SystemTray.items.values
        displayDate: panelClock.date
        onOpenChanged: { if (open) workspaceLayouts.refresh(); }
        services: desktop
        style: theme
        appearance: appearance
        displays: displayProfiles
        idlePreferences: idlePreferences
        searchModel: desktopSearch
        notifs: notifications
        keyboard: keyboard
        hyprControls: hyprControls
        actions: shellActions
        wallpaper: wallpaperState
    }
    PanelHotCorners { panel: launcher; style: theme }
    NotificationBanner { notifs: notifications; style: theme }
    OsdOverlay { shell: desktop; style: theme; searchModel: desktopSearch; layoutState: workspaceLayouts; controls: hyprControls }

    IpcHandler {
        target: "idle"
        function keepAwakeFor(minutes: int): bool { return desktop.keepAwakeFor(minutes); }
        function setKeepAwake(enabled: bool): bool { return desktop.setKeepAwake(enabled); }
        function status(): string {
            return JSON.stringify({ready: desktop.keepAwakeReady, keepAwake: desktop.keepAwake,
                until: desktop.keepAwakeUntil, permanent: desktop.keepAwakeRequested, inhibitorActive: desktop.keepAwakeInhibitorActive,
                deadlines: idlePreferences.values, overridden: idlePreferences.overridden, error: idlePreferences.error});
        }
    }

    IpcHandler {
        target: "displays"
        function status(): string { return displayProfiles.status(); }
        function apply(name: string): bool { return displayProfiles.activate(name); }
        function confirm(): bool { return displayProfiles.confirm(); }
        function revert(): bool { return displayProfiles.revert(); }
    }

    IpcHandler {
        target: "wallpaper"
        function showPicker(): void { launcher.openOnScreen(launcher.preferredScreen); launcher.navigate("wallpaper"); }
        function status(): string {
            return JSON.stringify({loaded: wallpaperState.loaded, error: wallpaperState.error || wallpaperExport.error,
                screens: Quickshell.screens.map(screen => ({name: screen.name, wallpaper: wallpaperState.entryFor(screen.name)}))});
        }
    }

    IpcHandler {
        target: "appearance"
        function setMode(mode: string): void {
            if (mode === "dark" || mode === "light") appearance.setTheme(mode === "dark");
        }
        function selectMode(mode: string): bool { return appearance.selectMode(mode); }
        function resumeAutomatic(): void { appearance.resumeAutomatic(); }
        function status(): string {
            return JSON.stringify({selectedMode: appearance.selectedMode, location: appearance.locationStatus,
                preferencesOverridden: appearance.preferencesOverridden, automatic: appearance.automatic, nextTransition: appearance.nextTransition,
                overrideUntil: appearance.overrideUntil, mode: appearance.darkMode ? "dark" : "light",
                ready: appearance.appearanceKnown, available: appearance.appearanceAvailable,
                error: appearance.appearanceError || appearanceExport.error});
        }
    }

    IpcHandler {
        target: "capture"
        function region(): bool { return capture.request(); }
    }
    IpcHandler {
        target: "launcher"
        function search(query: string): void { launcher.openSearch(query); }
        function toggle(): void { launcher.toggle(); }
        function close(): void { launcher.dismiss(); }
    }
}

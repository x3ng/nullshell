import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "components"
import "preview"

// The production view, synthetic state. Never instantiate shell.qml here.
ShellRoot {
    id: root
    PanelFixture { id: fixture; query: panel.query; onNavigateRequested: section => panel.navigate(section) }
    Theme { id: theme; darkMode: fixture.darkMode }
    QtObject {
        id: actionAdapter
        function available(action) { return true; }
        function execute(action) { fixture.execute(action); }
    }
    LauncherPanel {
        id: panel
        // Only the private headless test compositor requests exclusive focus.
        WlrLayershell.keyboardFocus: !open ? WlrKeyboardFocus.None
            : Quickshell.env("NULLSHELL_PREVIEW_EXCLUSIVE_KEYBOARD") === "1"
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
        preferredScreen: Quickshell.screens[0]
        displayDate: new Date(2026, 0, 15, 14, 35)
        trayItems: fixture.trayItems
        layerNamespace: "nullshell-preview-panel"
        style: theme
        services: fixture
        appearance: fixture
        searchModel: fixture
        hyprControls: fixture
        notifs: fixture
        keyboard: fixture
        actions: actionAdapter
        Component.onCompleted: Qt.callLater(() => panel.openOnScreen(panel.preferredScreen))
    }
    function findItem(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const found = findItem(child, name);
            if (found) return found;
        }
        return null;
    }
    IpcHandler {
        target: "preview"
        function openPanel(): void { panel.openOnScreen(panel.preferredScreen); }
        function close(): void { panel.dismiss(); }
        function quit(): void { Qt.quit(); }
        function page(name: string): void { panel.openOnScreen(panel.preferredScreen); panel.navigate(name); }
        function search(text: string): void { panel.openSearch(text); }
        function blur(enabled: bool): void { theme.previewBlur = enabled ? 1 : 0; }
        function light(enabled: bool): void { fixture.darkMode = !enabled; }
        function width(value: int): void { panel.maximumCardWidth = Math.max(360, Math.min(1000, value)); }
        function scenario(name: string): bool {
            if (!["normal", "empty", "crowded", "media"].includes(name)) return false;
            fixture.scenario = name;
            return true;
        }
        function tick(): void { fixture.titleRevision++; }
        function action(name: string): void { fixture.execute(name); }
        function activateControl(name: string): bool {
            const item = root.findItem(panel.contentItem, name);
            if (!item || !item.visible || item.available === false || typeof item.triggered !== "function") return false;
            item.triggered();
            return true;
        }
        function coordinate(name: string, value: string): bool {
            const item = root.findItem(panel.contentItem, "appearance-" + name);
            if (!item || !["latitude", "longitude"].includes(name)) return false;
            item.text = value;
            return true;
        }
        function appearanceState(name: string): void {
            fixture.selectMode("auto");
            fixture.appearanceError = "";
            fixture.nextTransition = 1794736800;
            if (name === "fixed") fixture.useFixedLocation(51.5, -0.1);
            else {
                fixture.useDeviceLocation();
                if (name === "unavailable") {
                    fixture.locationStatus = "unavailable";
                    fixture.nextTransition = null;
                    fixture.appearanceError = "Location unavailable; keeping current appearance";
                } else if (name === "locating") { fixture.locationStatus = "locating"; fixture.nextTransition = null; }
                else if (name === "override") fixture.overrideUntil = 1794736800;
            }
        }
        function capture(path: string): bool {
            const item = root.findItem(panel.contentItem, "launcher-card");
            return item ? item.grabToImage(result => result.saveToFile(path)) : false;
        }
        function status(): string {
            return JSON.stringify({open: panel.open, page: panel.pageKey, scenario: fixture.scenario,
                query: panel.query, results: fixture.results.length, card: panel.cardGeometry,
                selectedKey: panel.selectedKey, selectedIndex: panel.selectedIndex,
                blur: theme.backdropBlur, materialOpacity: theme.glassOpacity,
                appearanceMode: fixture.selectedMode, location: fixture.locationStatus, overrideUntil: fixture.overrideUntil,
                appearanceSettings: fixture.effectiveSettings, preferencesOverridden: fixture.preferencesOverridden,
                dark: fixture.darkMode, keepAwake: fixture.keepAwake, lastAction: fixture.lastAction});
        }
    }
}

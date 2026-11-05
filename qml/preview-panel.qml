import QtQuick
import Quickshell
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
        function status(): string {
            return JSON.stringify({open: panel.open, page: panel.pageKey, scenario: fixture.scenario,
                query: panel.query, results: fixture.results.length, card: panel.cardGeometry,
                selectedKey: panel.selectedKey, selectedIndex: panel.selectedIndex,
                blur: theme.backdropBlur, materialOpacity: theme.glassOpacity,
                dark: fixture.darkMode, keepAwake: fixture.keepAwake, lastAction: fixture.lastAction});
        }
    }
}

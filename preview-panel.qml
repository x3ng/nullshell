//@ pragma UseQApplication
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
        id: wallpaperFixture
        property bool loaded: true
        property bool saving: false
        property string error: ""
        signal saved()
        function entryFor(output) { return {path: "", fit: "cover"}; }
        function urlFor(path) { return path; }
        function apply(output, path, fit) { saved(); }
    }
    QtObject {
        id: actionAdapter
        readonly property var session: fixture.session
        function available(action) {
            if (action === "wifi-toggle") return fixture.wifiAvailable && !fixture.wifiBusy;
            if (action === "bluetooth-toggle") return fixture.bluetoothAvailable && !fixture.bluetoothBusy;
            if (["light", "dark", "appearance-resume"].includes(action)) return fixture.appearanceAvailable;
            return true;
        }
        function execute(action) { fixture.execute(action); }
    }
    LauncherPanel {
        id: panel
        // Only the private headless test compositor requests exclusive focus.
        WlrLayershell.keyboardFocus: !open || detailPages.dialogOpen ? WlrKeyboardFocus.None
            : Quickshell.env("NULLSHELL_PREVIEW_EXCLUSIVE_KEYBOARD") === "1"
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
        preferredScreen: Quickshell.screens[0]
        displayDate: new Date(2026, 0, 15, 14, 35)
        trayItems: fixture.trayItems
        layerNamespace: "nullshell-preview-panel"
        windowTitleSuffix: "nullshell preview"
        style: theme
        services: fixture
        appearance: fixture
        searchModel: fixture
        hyprControls: fixture
        notifs: fixture
        keyboard: fixture
        actions: actionAdapter
        wallpaper: wallpaperFixture
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
    function control(name) {
        const embedded = findItem(panel.contentItem, name);
        if (embedded) return embedded;
        for (const section of panel.detailPages.sections) {
            const item = panel.detailPages.pageItem(section);
            const found = item ? findItem(item, name) : null;
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
        function closeDetached(name: string): void { panel.detailPages.closeDetached(name); }
        function resizeDetached(name: string, width: int, height: int): void {
            const window = panel.detailPages.slot(name)?.window;
            if (window) { window.width = width; window.height = height; }
        }
        function scrollDetail(name: string): void {
            const page = panel.detailPages.pageItem(name);
            const view = page ? root.findItem(page, "detail-scroll") : null;
            if (view) view.contentY = Math.max(0, view.contentHeight - view.height);
        }
        function detailGeometry(name: string): string {
            const page = panel.detailPages.pageItem(name);
            const view = page ? root.findItem(page, "detail-scroll") : null;
            const image = page ? root.findItem(page, "wallpaper-preview") : null;
            return JSON.stringify({naturalHeight: page?.naturalHeight ?? 0,
                viewportHeight: view?.height ?? 0, contentHeight: view?.contentHeight ?? 0,
                scroll: view?.contentY ?? 0, imageWidth: image?.width ?? 0, imageHeight: image?.height ?? 0});
        }
        function focusControl(name: string, control: string): bool {
            const page = panel.detailPages.pageItem(name);
            const item = page ? root.findItem(page, control) : null;
            if (!item) return false;
            item.forceActiveFocus();
            return true;
        }
        function cancelFileDialog(): void {
            const picker = root.control("wallpaper-picker");
            if (picker) picker.cancelDialog();
        }
        function draft(name: string, value: string): bool {
            const item = panel.detailPages.pageItem("wallpaper");
            const picker = item ? root.findItem(item, "wallpaper-picker") : null;
            if (!picker || name !== "wallpaper") return false;
            picker.pendingPath = value;
            return true;
        }
        function captureDetached(name: string, path: string): bool {
            const item = panel.detailPages.pageItem(name);
            return item ? item.grabToImage(result => result.saveToFile(path)) : false;
        }
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
        function activateSelected(): void { panel.activate(panel.selectedIndex); }
        function footerGeometry(): string {
            const entries = root.findItem(panel.contentItem, "footer-entries");
            const tools = root.findItem(panel.contentItem, "footer-tools");
            return JSON.stringify({width: entries.width, toolsX: tools.x, toolsWidth: tools.width});
        }
        function scrollOverview(bottom: bool): void {
            const view = root.findItem(panel.contentItem, "overview-scroll");
            if (view) view.contentY = bottom ? Math.max(0, view.contentHeight - view.height) : 0;
        }
        function action(name: string): void { fixture.execute(name); }
        function quickState(name: string): void {
            fixture.wifiBusy = fixture.bluetoothBusy = name === "busy";
            fixture.wifiAvailable = fixture.bluetoothAvailable = fixture.appearanceAvailable = name !== "unavailable";
            fixture.wifiError = name === "error" ? "Could not change Wi-Fi state" : "";
            fixture.bluetoothError = name === "error" ? "Could not change Bluetooth state" : "";
        }
        function sessionState(name: string): void {
            fixture.session.busy = name === "busy";
            fixture.session.supported = name !== "unavailable";
            fixture.session.error = name === "error" ? "The session action was denied. Please try again." : "";
        }
        function activateControl(name: string): bool {
            const item = root.control(name);
            if (!item || !item.visible || item.available === false || typeof item.triggered !== "function") return false;
            item.triggered();
            return true;
        }
        function coordinate(name: string, value: string): bool {
            const item = root.control("appearance-" + name);
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
                detached: panel.detailPages.sections.filter(section => panel.detailPages.isDetached(section)),
                detachedFocus: panel.detailPages.sections.filter(section => panel.detailPages.isDetached(section)).map(section => ({section: section,
                    active: panel.detailPages.slot(section).window.active,
                    focusedItem: panel.detailPages.slot(section).window.activeFocusItem?.objectName ?? ""})),
                detachedWifi: panel.detachedWifi, detachedControls: panel.detachedControls,
                dialogOpen: panel.detailPages.dialogOpen,
                wallpaperDraft: root.control("wallpaper-picker")?.pendingPath ?? null,
                wallpaperApplied: root.control("wallpaper-picker")?.applied ?? false,
                latitudeDraft: root.control("appearance-latitude")?.text ?? null,
                query: panel.query, results: panel.results.length, card: panel.cardGeometry,
                commandFilter: panel.commandFilter, resultTypes: panel.results.map(row => row.actionType || row.kind),
                selectedKey: panel.selectedKey, selectedIndex: panel.selectedIndex,
                blur: theme.backdropBlur, materialOpacity: theme.glassOpacity,
                appearanceMode: fixture.selectedMode, location: fixture.locationStatus, overrideUntil: fixture.overrideUntil,
                appearanceSettings: fixture.effectiveSettings, preferencesOverridden: fixture.preferencesOverridden,
                dark: fixture.darkMode, keepAwake: fixture.keepAwake, lastAction: fixture.lastAction});
        }
    }
}

//@ pragma UseQApplication
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "components"
import "preview"

// The production view, synthetic state. Never instantiate shell.qml here.
ShellRoot {
    id: root
    PanelFixture { id: fixture; mixerVisible: panel.mixerVisible; query: panel.query; onNavigateRequested: section => panel.navigate(section) }
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
        id: displaysFixture
        property bool enabled: true
        property string phase: "idle"
        property string error: ""
        property string editorError: ""
        property bool editorLoading: false
        property bool verified: false
        signal editorTopologyChanged()
        property double previewUntil: 0
        property var submitted: []
        property var editorOutputs: [
            {name:"eDP-1",modes:["1920x1080@60Hz", "1280x720@60Hz"], current:{key:"fixture|panel",name:"eDP-1",enabled:true,width:1920,height:1080,refresh:60,x:0,y:0,scale:1,transform:0}},
            {name:"DP-1",modes:["2560x1440@60Hz", "1920x1080@60Hz"], current:{key:"fixture|external",name:"DP-1",enabled:true,width:2560,height:1440,refresh:60,x:1920,y:0,scale:1,transform:0}}
        ]
        function refreshEditor() {}
        function previewEditor(draft) { submitted = draft; previewUntil = Date.now() + 14000; verified = true; phase = "preview"; }
        function confirm() { phase = "idle"; fixture.lastAction = "display-confirm"; }
        function revert() { phase = "idle"; fixture.lastAction = "display-revert"; }
    }
    QtObject {
        id: idleFixture
        property bool ready: true
        property bool saving: false
        property bool overridden: false
        property string error: ""
        readonly property var defaults: ({dimSeconds:150,lockSeconds:300,displayOffSeconds:600})
        property var values: defaults
        function store(value) { overridden = value !== null; values = value ?? defaults; return true; }
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
        displays: displaysFixture
        idlePreferences: idleFixture
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
            const page = name === "overview" ? panel.contentItem : panel.detailPages.pageItem(name);
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
        function setToolField(name: string, value: string): bool {
            if (!["awake-duration", "shortcut-filter", "notification-filter"].includes(name)) return false;
            const field = root.control(name);
            if (field) field.text = value;
            return !!field;
        }
        function displayValue(name: string, value: string): bool {
            const editor = root.control("display-editor");
            if (!editor) return false;
            if (name === "mode") editor.setMode(value);
            else if (["scale", "x", "y"].includes(name)) editor.number(name, value);
            else return false;
            return true;
        }
        function displaySelect(index: int): bool {
            const picker = root.control("displays-output");
            if (!picker || index < 0 || index >= picker.count) return false;
            picker.activated(index);
            return true;
        }
        function idleValue(key: string, value: string): bool {
            const editor = root.control("idle-editor");
            if (!editor || !["dimSeconds", "lockSeconds", "displayOffSeconds"].includes(key)) return false;
            editor.edit(key, value);
            return true;
        }
        function idleReloadUnchanged(): void { idleFixture.values = Object.assign({}, idleFixture.values); }
        function shortcutCount(): int { return root.control("shortcut-list")?.matches.length ?? -1; }
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
            else if (name === "timezone") fixture.useTimezoneLocation();
            else {
                fixture.useIpLocation();
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
            const viewport = root.findItem(panel.contentItem, "overview-scroll");
            const focus = panel.contentItem.Window.window?.activeFocusItem;
            const point = focus && viewport ? focus.mapToItem(viewport, 0, 0) : null;
            return JSON.stringify({open: panel.open, page: panel.pageKey, scenario: fixture.scenario,
                doNotDisturb: fixture.doNotDisturb,
                focusedItem: focus?.objectName ?? "", overviewScroll: viewport?.contentY ?? 0,
                focusY: point?.y ?? 0, focusHeight: focus?.height ?? 0, overviewHeight: viewport?.height ?? 0,
                detached: panel.detailPages.sections.filter(section => panel.detailPages.isDetached(section)),
                detachedFocus: panel.detailPages.sections.filter(section => panel.detailPages.isDetached(section)).map(section => ({section: section,
                    active: panel.detailPages.slot(section).window.active,
                    focusedItem: panel.detailPages.slot(section).window.activeFocusItem?.objectName ?? ""})),
                mediaPlayer: root.control("media-pane")?.player?.identity ?? "",
                shuffle: root.control("media-shuffle")?.selected ?? false,
                repeatIcon: root.control("media-repeat")?.iconKind ?? "",
                repeating: root.control("media-repeat")?.selected ?? false,
                seekEnabled: root.control("media-position")?.enabled ?? false,
                mediaPosition: fixture.player?.position ?? 0,
                streamVolume: fixture.playbackStreams[0]?.audio.volume ?? 0,
                streamMuted: fixture.playbackStreams[0]?.audio.muted ?? false,
                savedKeys: fixture.history.map(entry => entry.recordKey),
                historyFilter: panel.detailPages.pageItem("notifications")?.historyQuery ?? "",
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
                displayPhase: displaysFixture.phase, displayDraft: displaysFixture.submitted,
                idleTimers: idleFixture.values, idleOverridden: idleFixture.overridden,
                dark: fixture.darkMode, keepAwake: fixture.keepAwake, lastAction: fixture.lastAction});
        }
    }
}

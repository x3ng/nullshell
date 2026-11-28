pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import ".."
import "../SearchQuery.js" as SearchQuery

PanelWindow {
    id: panel
    required property var services
    required property Theme style
    required property var appearance
    property var displays: null
    property var idlePreferences: null
    required property var searchModel
    required property var hyprControls
    required property var notifs
    required property var keyboard
    required property var actions
    required property var wallpaper
    property alias detailPages: controlDetails
    readonly property bool mixerVisible: controlDetails.pageItem("audio")?.mixerVisible ?? false
    readonly property bool detachedWifi: controlDetails.isDetached("wifi")
    readonly property bool detachedControls: controlDetails.sections.some(section => controlDetails.isDetached(section))
    required property var preferredScreen
    required property var trayItems
    required property date displayDate
    property string layerNamespace: "quickshell-launcher"
    property string windowTitleSuffix: "nullshell"
    property real maximumCardWidth: style.maximumPanelWidth
    readonly property real surfaceOpacity: style.glassOpacity
    readonly property rect cardGeometry: Qt.rect(card.x, card.y, card.width, card.height)
    property bool open: false
    property string homeTab: "overview"
    readonly property var homeTabDefinitions: [
        {key: "overview", label: "Quick controls"},
        {key: "desktop", label: "Desktop"}
    ]
    readonly property var detailSections: controlDetails.sections
    // Read actual StackLayout indices so adding/reordering a page cannot change
    // the meaning of navigation or page-specific lifecycle bindings.
    readonly property var pageIndexes: ({
        overview: overviewPage.StackLayout.index,
        search: searchResultsPage.StackLayout.index,
        details: controlDetails.StackLayout.index,
        desktop: desktopPage.StackLayout.index
    })
    property string controlSection: ""
    readonly property bool searching: query.trim().length > 0
    readonly property bool showingWorkspace: !showingDetails && !searching && homeTab === "desktop"
    readonly property bool showingDetails: controlSection !== ""
    readonly property int activePage: showingDetails ? pageIndexes.details
        : searching ? pageIndexes.search : pageIndexes[homeTab]
    property string query: ""
    property int selectedIndex: 0
    property var selectedKey: null
    property string selectionQuery: ""
    property int selectionRevision: 0
    readonly property var sink: services.sink
    readonly property var player: services.player
    readonly property bool commandScope: query.trim().startsWith(">")
    readonly property string commandFilter: SearchQuery.commandFilter(query)
    readonly property var results: searchModel.results

    function setCommandFilter(value) {
        if (!commandScope || !["all", "panel", "operation"].includes(value)) return;
        query = SearchQuery.withCommandFilter(query, value);
        Qt.callLater(() => { if (panel.open) { search.forceActiveFocus(); search.cursorPosition = search.text.length; } });
    }

    function handleKey(event) {
        if (!(event.modifiers & Qt.ControlModifier)) return;
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
            if (!searching) return;
            const index = event.key === Qt.Key_0 ? 9 : event.key - Qt.Key_1;
            activate(index);
            event.accepted = true;
            return;
        }
        switch (event.key) {
        case Qt.Key_N: panel.moveSelection(1); break;
        case Qt.Key_P: panel.moveSelection(-1); break;
        case Qt.Key_G: panel.dismiss(); break;
        default: return;
        }
        event.accepted = true;
    }

    function openSearch(text) {
        if (!open) {
            openOnScreen(preferredScreen);
        }
        homeTab = "overview";
        controlSection = "";
        query = text;
        Qt.callLater(() => { if (panel.open) { search.forceActiveFocus(); search.cursorPosition = search.text.length; } });
    }

    function toggle() {
        if (open) { dismiss(); return; }
        openOnScreen(preferredScreen);
    }
    function openOnScreen(targetScreen) {
        if (open || !targetScreen) return;
        screen = targetScreen;
        trayMenu.dismiss();
        controlSection = "";
        query = "";
        selectedIndex = 0;
        // Every invocation starts with the complete desktop state.
        homeTab = "overview";
        open = true;
        Qt.callLater(() => { if (panel.open && !panel.showingDetails) {
            if (panel.showingWorkspace) desktopPage.forceActiveFocus();
            else search.forceActiveFocus();
        } });
    }
    // Opening resets the route; dismissal unmaps the glass and its blur together.
    function dismiss() { trayMenu.dismiss(); open = false; }
    // The only route dispatcher. Commands and visible controls use this same
    // path; unknown route IDs must not create an empty or hidden page.
    function navigate(section) {
        if (homeTabDefinitions.some(page => page.key === section)) {
            selectHome(section);
            return true;
        }
        return showDetails(section);
    }
    function selectHome(tab) {
        if (!homeTabDefinitions.some(definition => definition.key === tab)) return;
        trayMenu.dismiss();
        homeTab = tab;
        query = "";
        controlSection = "";
        Qt.callLater(() => { if (panel.open && !panel.showingDetails) {
            if (panel.showingWorkspace) desktopPage.forceActiveFocus();
            else search.forceActiveFocus();
        } });
    }
    function returnToHome() {
        homeTab = "overview";
        query = "";
        controlSection = "";
        Qt.callLater(() => { if (panel.open && !panel.showingDetails) {
            if (panel.showingWorkspace) desktopPage.forceActiveFocus();
            else search.forceActiveFocus();
        } });
    }
    function showDetails(section) {
        if (!detailSections.includes(section)) return false;
        if (controlDetails.isDetached(section)) {
            dismiss();
            controlDetails.focusDetached(section);
            return true;
        }
        trayMenu.dismiss();
        query = "";
        controlSection = section;
        Qt.callLater(() => { if (panel.open && panel.showingDetails) controlDetails.forceActiveFocus(); });
        return true;
    }
    function handleEscape() {
        if (showingWorkspace && desktopPage.showingShortcuts) { desktopPage.showingShortcuts = false; return; }
        if (showingDetails || searching || homeTab !== "overview") returnToHome();
        else dismiss();
    }
    function moveSelection(delta) {
        if (!searching || !results.length) return;
        selectionRevision++;
        selectedIndex = (selectedIndex + delta + results.length) % results.length;
        selectedKey = results[selectedIndex].key;
        searchResultsPage.showSelection(selectedIndex);
    }
    function syncSelection(reset = false) {
        const sameQuery = !reset && selectionQuery === query;
        const previous = sameQuery ? results.findIndex(result => result.key === selectedKey) : -1;
        selectedIndex = previous >= 0 ? previous : sameQuery
            ? Math.min(selectedIndex, Math.max(0, results.length - 1)) : 0;
        selectedKey = results[selectedIndex]?.key ?? null;
        selectionQuery = query;
        // A retained result may move outside the old viewport after re-ranking.
        Qt.callLater(() => {
            if (panel.open && panel.searching) searchResultsPage.showSelection(selectedIndex);
        });
    }
    function resetSelection() {
        const revision = ++selectionRevision;
        selectedIndex = 0;
        selectedKey = null;
        selectionQuery = query;
        // query and the derived results can notify in either order. Do not
        // retain an identity from the old query while bindings are settling.
        Qt.callLater(() => {
            if (revision === selectionRevision) syncSelection(true);
        });
    }
    function activate(index, forceTerminal = false) {
        const result = results[index];
        if (!searching || !result || result.enabled === false) return;
        if (result.kind === "ACTION") {
            // Keep the row before clearing the query reshuffles the model.
            const previousQuery = query;
            query = "";
            const outcome = searchModel.activateResult(result, forceTerminal);
            if (!outcome.accepted) query = previousQuery;
        } else {
            const outcome = searchModel.activateResult(result, forceTerminal);
            if (outcome.accepted && outcome.closePanel) dismiss();
        }
    }
    onQueryChanged: {
        trayMenu.dismiss();
        controlSection = "";
        resetSelection();
        searchResultsPage.resetScroll();
    }
    onResultsChanged: syncSelection()

    visible: open
    property bool surfaceReady: false
    onVisibleChanged: {
        if (!visible) surfaceReady = false;
        else style.refreshMaterial();
    }
    // Only animate later page-height changes. The first mapped frame must
    // already contain the complete glass surface and its matching blur region.
    Connections {
        target: card.Window.window
        enabled: panel.open && !panel.surfaceReady
        function onFrameSwapped() { panel.surfaceReady = true; }
    }
    readonly property string pageKey: showingDetails ? "detail:" + controlSection
        : searching ? "search" : homeTab
    onPageKeyChanged: { if (open) pageEnter.restart(); }
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    // Respect the screen keyboard's exclusive zone so the backdrop never
    // covers its keys, even when this overlay is mapped after the keyboard.
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.layer: controlDetails.dialogOpen ? WlrLayer.Bottom : WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open && !controlDetails.dialogOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: layerNamespace

    Region {
        id: panelBlurRegion
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        radius: card.radius
    }
    BackgroundEffect.blurRegion: panel.visible && panel.style.backdropBlur ? panelBlurRegion : null

    TrayMenuPopup { id: trayMenu; style: panel.style; panelWindow: panel }
    onTrayItemsChanged: {
        if (trayMenu.owner && !trayItems.includes(trayMenu.owner)) trayMenu.dismiss();
    }


    MouseArea {
        // Outside clicks dismiss the panel without dimming the desktop.
        anchors.fill: parent
        enabled: panel.open && !controlDetails.dialogOpen
        onClicked: panel.dismiss()
    }

    MaterialSurface {
        id: card
        objectName: "launcher-card"
        materialTheme: panel.style
        materialOpacity: panel.surfaceOpacity
        shadowEnabled: true
        enabled: panel.open
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        // Keep the search field stationary as status/search content changes height.
        anchors.topMargin: Math.max(16, Math.round(parent.height * 0.18))
        width: Math.min(panel.maximumCardWidth, parent.width - 32)
        readonly property int inset: panel.style.panelPadding
        readonly property int bottomInset: panel.activePage === panel.pageIndexes.overview && overviewPage.hasFooter ? 10 : inset
        readonly property real contentHeight: panel.showingDetails ? controlDetails.naturalHeight
            : panel.searching ? searchResultsPage.naturalHeight
            : panel.homeTab === "desktop" ? desktopPage.naturalHeight
            : overviewPage.naturalHeight
        readonly property real chromeHeight: panel.showingDetails || panel.showingWorkspace ? 0
            : searchStrip.implicitHeight + (footer.visible ? footer.implicitHeight : 0)
                + panel.style.panelGap * (footer.visible ? 2 : 1)
        // Fit the active page; long content scrolls under the shared screen limit.
        readonly property real targetHeight: Math.max(0, Math.min(panel.style.maximumPanelHeight,
            parent.height - anchors.topMargin - 16,
            contentHeight + chromeHeight + card.inset + card.bottomInset))
        property real layoutHeight: 0
        Binding {
            target: card
            property: "layoutHeight"
            value: card.targetHeight
            when: panel.open
            restoreMode: Binding.RestoreNone
        }
        height: layoutHeight
        Behavior on height {
            enabled: panel.open && panel.surfaceReady
            NumberAnimation { duration: panel.style.motionResize; easing.type: Easing.OutCubic }
        }
        clip: true
        radius: panel.style.radiusPanel
        border.color: panel.style.materialEdge
        border.width: 1
        // Stop clicks in blank areas reaching the outside-dismiss handler.
        MouseArea { anchors.fill: parent }
        Keys.onEscapePressed: panel.handleEscape()
        Keys.onPressed: event => panel.handleKey(event)

        ColumnLayout {
            id: bodyLayout
            // Lay out once at the destination height. The animated outer card
            // reveals/clips it instead of squeezing every row on every frame.
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.margins: card.inset
            height: Math.max(0, card.layoutHeight - card.inset - card.bottomInset)
            spacing: panel.style.panelGap

            Rectangle {
                id: searchStrip
                objectName: "launcher-search"
                readonly property bool emptyQuery: search.text.length === 0 && search.preeditText.length === 0
                readonly property string bareScope: search.preeditText.length === 0
                    && (panel.query.trim() === "@" || panel.query.trim() === "/") ? panel.query.trim() : ""
                visible: !panel.showingDetails && !panel.showingWorkspace
                Layout.fillWidth: true
                implicitHeight: panel.style.fieldHeight
                Layout.preferredHeight: implicitHeight
                Layout.minimumHeight: implicitHeight
                Layout.maximumHeight: implicitHeight
                radius: panel.style.radiusInput
                color: panel.style.inputSurface
                border.width: 1
                // A typed query strengthens the edge; the default auto-focus stays calm.
                border.color: search.text.length > 0 ? panel.style.outline : panel.style.fieldOutline
                StatusIcon {
                    anchors.left: parent.left
                    anchors.leftMargin: panel.style.spaceMd
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    kind: "search"
                    ink: search.text.length > 0 ? panel.style.textPrimary : panel.style.textMuted
                }
                EmacsInput {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: 40
                    anchors.rightMargin: scopeHints.visible ? scopeHints.implicitWidth + 14 : panel.style.spaceMd
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: panel.style.fontFamily
                    font.pixelSize: panel.style.fontSizeSearch
                    font.weight: Font.Medium
                    color: panel.style.textPrimary
                    selectionColor: panel.style.surfaceSelected
                    selectedTextColor: panel.style.textSelected
                    clip: true
                    text: panel.query
                    onTextChanged: panel.query = text
                    onShortcut: event => panel.handleKey(event)
                    Keys.onDownPressed: panel.moveSelection(1)
                    Keys.onUpPressed: panel.moveSelection(-1)
                    Keys.onReturnPressed: event => panel.activate(panel.selectedIndex, !!(event.modifiers & Qt.ShiftModifier))
                    Keys.onEnterPressed: event => panel.activate(panel.selectedIndex, !!(event.modifiers & Qt.ShiftModifier))
                    Keys.onEscapePressed: panel.handleEscape()
                    Accessible.name: "Search apps, windows and commands"
                    cursorDelegate: Rectangle {
                        implicitWidth: 1.5
                        color: panel.style.accent
                        visible: search.text.length > 0 || search.preeditText.length > 0
                    }

                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: search.anchors.leftMargin
                    anchors.rightMargin: 6
                    spacing: panel.style.spaceSm
                    visible: panel.commandScope || searchStrip.bareScope !== "" || searchStrip.emptyQuery
                    SearchStatus {
                        id: searchStatus
                        objectName: "search-status"
                        visible: searchStrip.emptyQuery
                        style: panel.style
                        services: panel.services
                        date: panel.displayDate
                        expanded: searchStrip.width >= 520
                    }
                    Item { Layout.fillWidth: true; Layout.minimumWidth: 0 }
                    RowLayout {
                        id: scopeHints
                        spacing: panel.style.spaceXs
                        Repeater {
                            model: panel.commandScope ? [
                                {prefix: ">", label: "All", filter: "all"},
                                {prefix: ">?", label: "Panels", filter: "panel"},
                                {prefix: ">!", label: "Actions", filter: "operation"}
                            ].filter(hint => hint.filter !== panel.commandFilter) : [
                                {prefix: "@", label: "Windows", shortLabel: "Windows"},
                                {prefix: ">", label: "Commands", shortLabel: "Commands"},
                                {prefix: "/", label: "Applications", shortLabel: "Apps"}
                            ].filter(hint => hint.prefix !== searchStrip.bareScope)
                            ChoiceButton {
                                id: scopeHint
                                required property var modelData
                                readonly property var hint: modelData || ({prefix: "", label: "", shortLabel: "", filter: ""})
                                readonly property bool showLabel: panel.commandScope || searchStrip.width >= 500
                                objectName: panel.commandScope ? "command-filter-" + hint.filter : "search-scope-" + hint.prefix
                                Layout.preferredHeight: 28
                                Layout.preferredWidth: Math.max(26, hintRow.implicitWidth + 12)
                                compact: true
                                style: panel.style
                                label: ""
                                tooltip: panel.commandScope
                                    ? (hint.filter === "all" ? "All commands · Type >" : hint.label + " · Type " + hint.prefix + " to filter")
                                    : "Search " + hint.label.toLowerCase() + " · Type " + hint.prefix + " to filter"
                                Accessible.name: "Search " + hint.label.toLowerCase()
                                onTriggered: panel.commandScope ? panel.setCommandFilter(hint.filter) : panel.openSearch(hint.prefix + " ")
                                Row {
                                    id: hintRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Rectangle {
                                        width: Math.max(18, prefixText.implicitWidth + 8)
                                        height: 18
                                        anchors.verticalCenter: parent.verticalCenter
                                        radius: panel.style.radiusSmall
                                        color: panel.style.keycapSurface
                                        Text {
                                            id: prefixText
                                            anchors.centerIn: parent
                                            text: scopeHint.hint.prefix
                                            color: panel.style.accent
                                            font.family: panel.style.fontFamily
                                            font.pixelSize: panel.style.fontSizeCaption
                                            font.weight: Font.Bold
                                        }
                                    }
                                    Text {
                                        visible: scopeHint.showLabel
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: scopeHint.hint.shortLabel || scopeHint.hint.label
                                        color: scopeHint.hovered ? panel.style.textPrimary : panel.style.textMuted
                                        font.family: panel.style.fontFamily
                                        font.pixelSize: panel.style.fontSizeCaption
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }
                    }
                }

            }

            StackLayout {
                id: pages
                property real revealProgress: 1
                opacity: revealProgress
                transform: Translate { y: panel.style.motionDistance * (1 - pages.revealProgress) }
                NumberAnimation {
                    id: pageEnter
                    target: pages
                    property: "revealProgress"
                    from: 0
                    to: 1
                    duration: panel.style.motionPage
                    easing.type: Easing.OutCubic
                }
                Layout.minimumHeight: 0
                Layout.minimumWidth: 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                currentIndex: panel.activePage
                OverviewPage {
                    id: overviewPage
                    style: panel.style
                    services: panel.services
                    actions: panel.actions
                    notifs: panel.notifs
                    appearance: panel.appearance
                    keyboard: panel.keyboard
                    searchModel: panel.searchModel
                    controls: panel.hyprControls
                    trayItems: panel.trayItems
                    onMenuRequested: (owner, right, top) => {
                        const pos = overviewPage.mapToItem(panel.contentItem, right, top);
                        const showMenu = () => trayMenu.openFor(owner, pos.x, pos.y);
                        if (!showMenu()) Qt.callLater(showMenu);
                    }
                    panelOpen: panel.open && panel.activePage === panel.pageIndexes.overview
                    onWorkspaceManageRequested: address => {
                        desktopPage.selectedWorkspaceAddress = address;
                        panel.selectHome("desktop");
                    }
                    onDismissRequested: panel.dismiss()
                }
                SearchResultsPage {
                    id: searchResultsPage
                    style: panel.style
                    results: panel.results
                    searchModel: panel.searchModel
                    selectedIndex: panel.selectedIndex
                    active: panel.searching && !panel.showingDetails
                    commandScope: panel.commandScope
                    onActivateRequested: index => panel.activate(index)
                }
                DetailPages {
                    id: controlDetails
                    panel: panel
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                }
                DesktopPage {
                    id: desktopPage
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    style: panel.style
                    searchModel: panel.searchModel
                    controls: panel.hyprControls
                    actions: panel.actions
                    panelOpen: panel.open && panel.activePage === panel.pageIndexes.desktop
                    onBackRequested: panel.returnToHome()
                    onDismissRequested: panel.dismiss()
                }
            }
            PanelFooter {
                id: footer
                visible: panel.searching && !panel.showingDetails
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                Layout.minimumHeight: implicitHeight
                Layout.maximumHeight: implicitHeight
                style: panel.style
            }
        }
    }
}

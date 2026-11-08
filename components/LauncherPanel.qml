pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: panel
    required property var services
    required property Theme style
    required property var appearance
    required property var searchModel
    required property var hyprControls
    required property var notifs
    required property var keyboard
    required property var actions
    required property var preferredScreen
    required property var trayItems
    required property date displayDate
    property string layerNamespace: "quickshell-launcher"
    property real maximumCardWidth: style.maximumPanelWidth
    readonly property rect cardGeometry: Qt.rect(card.x, card.y, card.width, card.height)
    property bool open: false
    property string homeTab: "overview"
    readonly property var homeTabDefinitions: [
        {key: "overview", label: "Overview"},
        {key: "desktop", label: "Desktop"}
    ]
    readonly property var detailSections: ["wifi", "bluetooth", "audio", "notifications"]
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
    readonly property var results: searchModel.results

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
        Qt.callLater(() => { if (panel.open) search.forceActiveFocus(); });
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
        trayMenu.dismiss();
        query = "";
        controlSection = section;
        Qt.callLater(() => { if (panel.open && panel.showingDetails) controlDetails.forceActiveFocus(); });
        return true;
    }
    function handleEscape() {
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
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
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
        enabled: panel.open
        onClicked: panel.dismiss()
    }

    MaterialSurface {
        id: card
        materialTheme: panel.style
        materialOpacity: panel.style.glassOpacity
        enabled: panel.open
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        // Keep the search field stationary as status/search content changes height.
        anchors.topMargin: Math.max(16, Math.round(parent.height * 0.18))
        width: Math.min(panel.maximumCardWidth, parent.width - 32)
        readonly property real contentHeight: panel.showingDetails ? controlDetails.naturalHeight
            : panel.searching ? searchResultsPage.naturalHeight
            : panel.homeTab === "desktop" ? desktopPage.naturalHeight
            : overviewPage.naturalHeight
        readonly property real chromeHeight: panel.showingDetails || panel.showingWorkspace ? 0
            : searchStrip.implicitHeight + footer.implicitHeight + panel.style.panelGap * 2
        // Fit the active page; long content scrolls under the shared screen limit.
        readonly property real targetHeight: Math.max(0, Math.min(panel.style.maximumPanelHeight,
            parent.height - anchors.topMargin - 16,
            contentHeight + chromeHeight + panel.style.panelPadding * 2))
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
            anchors.margins: panel.style.panelPadding
            height: Math.max(0, card.layoutHeight - panel.style.panelPadding * 2)
            spacing: panel.style.panelGap

            Rectangle {
                id: searchStrip
                visible: !panel.showingDetails && !panel.showingWorkspace
                Layout.fillWidth: true
                implicitHeight: 44
                Layout.preferredHeight: implicitHeight
                Layout.minimumHeight: implicitHeight
                Layout.maximumHeight: implicitHeight
                radius: panel.style.radiusInput
                color: "transparent"
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 1
                    color: panel.style.separator
                }
                EmacsInput {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 4
                    anchors.topMargin: panel.style.spaceSm
                    anchors.bottomMargin: panel.style.spaceSm
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: panel.style.fontFamily
                    font.pixelSize: 18
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
                        implicitWidth: 1
                        color: panel.style.textPrimary
                        visible: search.text.length > 0 || search.preeditText.length > 0
                    }

                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 4
                    spacing: 12
                    visible: search.text.length === 0 && search.preeditText.length === 0
                    SearchStatus {
                        style: panel.style
                        services: panel.services
                        date: panel.displayDate
                        expanded: searchStrip.width >= 600
                    }
                    Item { Layout.fillWidth: true; Layout.minimumWidth: 0 }
                    RowLayout {
                        spacing: 6
                        Repeater {
                            model: [
                                {prefix: "@", label: "Windows"},
                                {prefix: ">", label: "Commands"},
                                {prefix: "/", label: "Applications"}
                            ]
                            ChoiceButton {
                                required property var modelData
                                Layout.preferredHeight: 28
                                Layout.preferredWidth: hintText.implicitWidth + 14
                                style: panel.style
                                label: ""
                                tooltip: "Search " + modelData.label.toLowerCase() + " · Type " + modelData.prefix + " to filter"
                                Accessible.name: "Search " + modelData.label.toLowerCase()
                                onTriggered: panel.openSearch(modelData.prefix + " ")
                                Text {
                                    id: hintText
                                    anchors.centerIn: parent
                                    text: modelData.prefix + (searchStrip.width >= 600 ? " " + modelData.label : "")
                                    color: panel.style.textSecondary
                                    font.family: panel.style.fontFamily
                                    font.pixelSize: 12
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
                    date: panel.displayDate
                    style: panel.style
                    services: panel.services
                    actions: panel.actions
                    appearance: panel.appearance
                    notifs: panel.notifs
                    searchModel: panel.searchModel
                    controls: panel.hyprControls
                    panelOpen: panel.open && panel.activePage === panel.pageIndexes.overview
                    onDismissRequested: panel.dismiss()
                }
                SearchResultsPage {
                    id: searchResultsPage
                    style: panel.style
                    results: panel.results
                    searchModel: panel.searchModel
                    selectedIndex: panel.selectedIndex
                    active: panel.searching && !panel.showingDetails
                    onActivateRequested: index => panel.activate(index)
                }
                ControlDetails {
                    id: controlDetails
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    style: panel.style
                    services: panel.services
                    actions: panel.actions
                    notifs: panel.notifs
                    section: panel.controlSection
                    panelOpen: panel.open && panel.showingDetails
                    retainContent: panel.visible && panel.activePage === panel.pageIndexes.details
                    onDismissRequested: panel.returnToHome()
                    onClosePanelRequested: panel.dismiss()
                    Keys.onPressed: event => panel.handleKey(event)
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
                visible: !panel.showingDetails && !panel.showingWorkspace
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                Layout.minimumHeight: implicitHeight
                Layout.maximumHeight: implicitHeight
                style: panel.style
                services: panel.services
                appearance: panel.appearance
                searchMode: panel.searching
                summaryOnly: true
                centerActions: panel.homeTab === "overview"
                notificationCount: panel.notifs.current.length
                notificationHistoryCount: panel.notifs.history.length
                lockAvailable: panel.actions.available("lock")
                onNotificationsRequested: panel.showDetails("notifications")
                onLockRequested: panel.actions.execute("lock")
                onAppearanceRequested: panel.actions.execute(panel.appearance.darkMode ? "light" : "dark")
                onKeepAwakeRequested: panel.actions.execute("keep-awake")
                trayItems: panel.trayItems
                date: panel.displayDate
                onMenuRequested: (owner, right, top) => {
                    const pos = footer.mapToItem(panel.contentItem, right, top);
                    const showMenu = () => trayMenu.openFor(owner, pos.x, pos.y);
                    if (!showMenu()) Qt.callLater(showMenu);
                }
            }
        }
    }
}

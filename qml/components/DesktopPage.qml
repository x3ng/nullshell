pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import ".."

ColumnLayout {
    id: page
    required property Theme style
    required property var searchModel
    required property var controls
    required property var actions
    required property bool panelOpen
    // Retain the last page snapshot while closed; background focus changes
    // must not rebuild invisible workspace and window delegates.
    property var displayedWorkspaces: []
    property var displayedWindows: []
    Binding {
        target: page; property: "displayedWorkspaces"
        value: page.controls.workspaces
        when: page.panelOpen
        restoreMode: Binding.RestoreNone
    }
    Binding {
        target: page; property: "displayedWindows"
        value: page.controls.windows
        when: page.panelOpen
        restoreMode: Binding.RestoreNone
    }
    // The layout picker has an explicit target; the overview always shows every workspace.
    property string selectedWorkspaceAddress: ""
    property string expandedAddress: ""
    // Keep inline actions with their window address, not with a disposable delegate.
    property string windowActionMode: ""
    property int pendingDismissRequestId: 0
    property string pendingDismissAddress: ""
    property bool choosingWorkspace: false
    property bool choosingLayout: false
    property string pendingWorkspaceAddress: ""
    property int pendingWorkspaceRequestId: 0
    readonly property var selectedWorkspace: controls.workspaces.find(w => w.address === selectedWorkspaceAddress) ?? null
    readonly property real naturalHeight: detailHeader.implicitHeight + spacing + content.implicitHeight
    spacing: 10
    signal backRequested()
    signal dismissRequested()

    function ensureSelection(reset) {
        // panelOpen can be assigned before required services during construction.
        if (!controls) return;
        if (!reset && selectedWorkspace) return;
        const workspace = controls.workspaces.find(w => w.address === controls.focusedWorkspaceAddress)
            ?? controls.workspaces.find(w => w.active && w.special)
            ?? controls.workspaces.find(w => w.active) ?? controls.workspaces[0];
        selectedWorkspaceAddress = workspace?.address ?? "";
    }

    function focusWindow(address) {
        if (!controls.busy && controls.focusWindow(address)) {
            pendingDismissRequestId = controls.lastRequestId;
            pendingDismissAddress = address;
        }
    }

    function openWorkspace(id) {
        if (controls.focusWorkspace(id)) {
            pendingWorkspaceAddress = id;
            pendingWorkspaceRequestId = controls.lastRequestId;
            choosingWorkspace = false;
        }
    }

    Component.onCompleted: ensureSelection(true)
    onExpandedAddressChanged: windowActionMode = ""
    onSelectedWorkspaceAddressChanged: choosingLayout = false
    onPanelOpenChanged: {
        pendingDismissRequestId = 0;
        pendingDismissAddress = "";
        pendingWorkspaceAddress = "";
        pendingWorkspaceRequestId = 0;
        choosingWorkspace = false;
        choosingLayout = false;
        expandedAddress = "";
        if (panelOpen) { ensureSelection(true); viewport.contentY = 0; }
    }
    Connections {
        target: page.controls
        function onWorkspacesChanged() { page.ensureSelection(false); }
        function onWindowsChanged() {
            if (!page.controls.windows.some(w => w.address === page.expandedAddress)) page.expandedAddress = "";
            if (page.pendingDismissAddress && !page.controls.windows.some(w => w.address === page.pendingDismissAddress)) {
                page.pendingDismissRequestId = 0;
                page.pendingDismissAddress = "";
            }
        }
        function onOperationFinished(success, operation, target, requestId, message) {
            if (page.pendingWorkspaceRequestId && requestId === page.pendingWorkspaceRequestId) {
                page.pendingWorkspaceAddress = "";
                page.pendingWorkspaceRequestId = 0;
                if (success && page.panelOpen) page.dismissRequested();
            }
            if (!page.pendingDismissRequestId || requestId !== page.pendingDismissRequestId) return;
            page.pendingDismissRequestId = 0;
            page.pendingDismissAddress = "";
            if (success && page.panelOpen) page.dismissRequested();
        }
    }

    DetailHeader {
        id: detailHeader
        style: page.style
        title: "Workspaces"
        subtitle: page.controls.workspaces.length + (page.controls.workspaces.length === 1 ? " workspace · " : " workspaces · ")
            + page.controls.windows.length + (page.controls.windows.length === 1 ? " window" : " windows")
        onBackRequested: page.backRequested()
        actions: [ChoiceButton {
            Layout.preferredWidth: 132
            Layout.preferredHeight: 30
            visible: page.controls.workspaceTargets.some(w => !w.exists)
            style: page.style
            label: "＋ New workspace"
            selected: page.choosingWorkspace
            available: page.controls.available && !page.controls.busy
            onTriggered: page.choosingWorkspace = !page.choosingWorkspace
        }]
    }

    ClippingRectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        implicitHeight: content.implicitHeight
        radius: page.style.radiusCard
        color: "transparent"
        Flickable {
            id: viewport
            anchors.fill: parent
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: content
                width: viewport.width
                spacing: page.style.spaceMd

                Flow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    visible: page.choosingWorkspace
                    spacing: page.style.spaceXs
                    Repeater {
                        model: page.controls.workspaceTargets.filter(w => !w.exists)
                        ChoiceButton {
                            required property var modelData
                            width: 44
                            style: page.style
                            label: modelData.name
                            filled: true
                            available: !page.controls.busy
                            onTriggered: page.openWorkspace(modelData.address)
                        }
                    }
                }
                Text {
                    visible: page.controls.error !== ""
                    Layout.fillWidth: true
                    text: page.controls.error
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: page.style.accentWarm
                    font.family: page.style.fontFamily
                    font.pixelSize: page.style.fontSizeBody
                }
                ColumnLayout {
                    id: workspaceGrid
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    spacing: 10
                    FontMetrics {
                        id: windowTitleMetrics
                        font.family: page.style.fontFamily
                        font.pixelSize: page.style.fontSizeBody
                        font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: StableRows { rows: page.displayedWorkspaces; keyField: "address" }
                        GroupCard {
                            id: workspaceCard
                            required property var record
                            readonly property var modelData: record
                            readonly property var windows: page.displayedWindows.filter(w => w.workspaceAddress === modelData.address)
                            objectName: "workspace-" + modelData.address
                            Layout.fillWidth: true
                            style: page.style
                            color: page.style.surfaceRaised
                            pad: 10
                            contentSpacing: page.style.spaceXs

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: page.style.spaceXs
                                Item {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 32
                                    implicitHeight: 28
                                    Text {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        text: workspaceCard.modelData.name
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        color: workspaceCard.modelData.active ? page.style.accent : page.style.textPrimary
                                        font.family: page.style.fontFamily
                                        font.pixelSize: page.style.fontSizeBody
                                        font.weight: Font.DemiBold
                                    }
                                    MouseArea {
                                        objectName: "focus-workspace-" + workspaceCard.modelData.address
                                        anchors.fill: parent
                                        enabled: page.controls.available && !page.controls.busy
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: page.openWorkspace(workspaceCard.modelData.address)
                                    }
                                }
                                ChoiceButton {
                                    Layout.preferredWidth: Math.min(100, workspaceCard.width * 0.48)
                                    Layout.preferredHeight: 28
                                    style: page.style
                                    objectName: "layout-workspace-" + workspaceCard.modelData.address
                                    label: (workspaceCard.modelData.layout ?? "—") + "  ▾"
                                    selected: page.choosingLayout && page.selectedWorkspaceAddress === workspaceCard.modelData.address
                                    available: page.controls.available && !page.controls.busy && !!workspaceCard.modelData.exists
                                    onTriggered: {
                                        const wasOpen = page.choosingLayout && page.selectedWorkspaceAddress === workspaceCard.modelData.address;
                                        page.selectedWorkspaceAddress = workspaceCard.modelData.address;
                                        page.choosingLayout = !wasOpen;
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: (workspaceCard.modelData.monitor ? workspaceCard.modelData.monitor + " · " : "")
                                    + workspaceCard.windows.length + (workspaceCard.windows.length === 1 ? " window" : " windows")
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: page.style.textMuted
                                font.family: page.style.fontFamily
                                font.pixelSize: page.style.fontSizeSmall
                            }
                            GridLayout {
                                visible: page.choosingLayout && page.selectedWorkspaceAddress === workspaceCard.modelData.address
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: page.style.spaceXs
                                rowSpacing: page.style.spaceXs
                                Repeater {
                                    model: ["dwindle", "master", "scrolling", "monocle"]
                                    ChoiceButton {
                                        required property string modelData
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        style: page.style
                                        label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                        selected: workspaceCard.modelData.layout === modelData
                                        available: page.controls.available && !page.controls.busy
                                        onTriggered: {
                                            if (page.controls.setLayout(workspaceCard.modelData.address, modelData)) page.choosingLayout = false;
                                        }
                                    }
                                }
                            }
                            Flow {
                                id: windowFlow
                                Layout.fillWidth: true
                                Layout.preferredHeight: implicitHeight
                                spacing: 6
                                Repeater {
                                    model: StableRows { rows: workspaceCard.windows; keyField: "address" }
                                    DesktopWindowCard {
                                        required property var record
                                        readonly property var modelData: record
                                        objectName: "window-" + modelData.address
                                        width: Math.min(windowFlow.width, expanded ? Math.max(300, naturalWidth) : naturalWidth)
                                        property real naturalWidth: 150
                                        Component.onCompleted: naturalWidth = Math.max(150,
                                            windowTitleMetrics.advanceWidth(modelData.title || modelData.appId || "Untitled window") + 104)
                                        height: implicitHeight
                                        style: page.style
                                        windowData: modelData
                                        controls: page.controls
                                        searchModel: page.searchModel
                                        expanded: page.expandedAddress === modelData.address
                                        actionMode: expanded ? page.windowActionMode : ""
                                        onExpandRequested: page.expandedAddress = expanded ? "" : modelData.address
                                        onModeRequested: mode => {
                                            if (page.expandedAddress === modelData.address) page.windowActionMode = mode;
                                        }
                                        onFocusRequested: address => page.focusWindow(address)
                                    }
                                }
                            }
                            Item {
                                visible: workspaceCard.windows.length === 0
                                Layout.fillWidth: true
                                implicitHeight: 32
                                Text {
                                    anchors.centerIn: parent
                                    text: "Empty workspace"
                                    color: page.style.textMuted
                                    font.family: page.style.fontFamily
                                    font.pixelSize: page.style.fontSizeSmall
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: page.controls.available && !page.controls.busy
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: page.openWorkspace(workspaceCard.modelData.address)
                                }
                            }
                        }
                    }
                }
                Text {
                    visible: page.controls.workspaces.length === 0
                    Layout.fillWidth: true
                    text: "No workspaces available."
                    color: page.style.textSecondary
                    font.family: page.style.fontFamily
                    font.pixelSize: page.style.fontSizeBody
                }
                ChoiceButton {
                    Layout.fillWidth: true
                    style: page.style
                    label: "Lock screen"
                    filled: true
                    available: page.actions.available("lock")
                    onTriggered: {
                        if (page.actions.execute("lock")) {
                            page.pendingDismissRequestId = page.controls.lastRequestId;
                            page.pendingDismissAddress = "";
                        }
                    }
                }
            }
        }
    }
}

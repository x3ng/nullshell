pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import Quickshell.Widgets
import ".."

// Quick actions are separate from the labelled detail-navigation targets.
// Full lists and less frequent commands remain in details and global search.
ColumnLayout {
    id: page
    required property Theme style
    required property var services
    required property var actions
    required property var appearance
    required property var notifs
    required property var searchModel
    required property var trayItems
    signal menuRequested(var owner, real right, real top)
    required property var controls
    required property date date
    required property bool panelOpen
    signal dismissRequested
    readonly property real naturalHeight: content.implicitHeight
    readonly property var system: services.controls
    readonly property var player: services.player
    readonly property var sink: services.sink
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
    onPanelOpenChanged: if (panelOpen) viewport.contentY = 0
    function revealFocus() {
        if (!panelOpen) return;
        const item = page.Window.window?.activeFocusItem;
        if (!item) return;
        let ancestor = item;
        while (ancestor && ancestor !== content) ancestor = ancestor.parent;
        if (!ancestor) return;
        const point = item.mapToItem(viewport, 0, 0);
        if (point.y < 0) viewport.contentY += point.y;
        else if (point.y + item.height > viewport.height) viewport.contentY += point.y + item.height - viewport.height;
        viewport.contentY = Math.max(0, Math.min(viewport.contentY, viewport.contentHeight - viewport.height));
    }
    Connections {
        target: page.Window.window
        function onActiveFocusItemChanged() { Qt.callLater(page.revealFocus); }
    }
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        implicitHeight: page.naturalHeight
        Flickable {
            id: viewport
            objectName: "overview-scroll"
            anchors.fill: parent
            contentWidth: width
            contentHeight: content.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            ColumnLayout {
                id: content
                width: viewport.width
                spacing: page.style.spaceMd
                ConnectivitySummary {
                    Layout.fillWidth: true
                    style: page.style
                    actions: page.actions
                    system: page.system
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: width < 500 ? 1 : 2
                    columnSpacing: page.style.spaceLg
                    rowSpacing: page.style.spaceSm
                    OverviewLevelControl {
                        style: page.style
                        actions: page.actions
                        title: "Volume"
                        icon: "volume"
                        value: page.sink?.audio?.volume ?? 0
                        available: !!page.sink?.audio
                        muted: page.sink?.audio?.muted ?? false
                        action: "output-mute"
                        detailsAction: "audio"
                        detailsTooltip: "Audio devices and microphone"
                        onEdited: value => page.services.setVolume(value)
                    }
                    OverviewLevelControl {
                        style: page.style
                        actions: page.actions
                        title: "Brightness"
                        icon: "brightness"
                        value: Math.max(0, page.services.brightness)
                        available: page.services.brightness >= 0
                        detailsAction: "appearance"
                        detailsTooltip: "Appearance settings"
                        onEdited: value => page.services.setBrightness(value)
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    ChoiceButton {
                        id: notificationGlance
                        objectName: "overview-notifications"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 64
                        Layout.preferredHeight: 40
                        style: page.style
                        label: ""
                        Accessible.name: "Notifications, " + page.notifs.current.length + " pending"
                        tooltip: page.notifs.current.length
                            ? (page.notifs.current[0].appName || "Application") + " · " + (page.notifs.current[0].summary || "Notification")
                            : "No pending notifications · Open history"
                        onTriggered: page.actions.execute("notifications")
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 0
                            anchors.rightMargin: page.style.spaceXs
                            spacing: page.style.spaceMd
                            Item {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 32
                                StatusIcon {
                                    anchors.centerIn: parent
                                    kind: "bell"
                                    ink: page.style.textMuted
                                    width: 20; height: 20
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                visible: notificationGlance.width >= 110
                                text: page.notifs.current.length
                                    ? String(page.notifs.current[0].summary || "Notification").replace(/\s+/g, " ")
                                    : "No notifications"
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: page.style.textSecondary
                                font.family: page.style.fontFamily
                                font.pixelSize: page.style.fontSizeBody
                            }
                            Text {
                                text: page.notifs.current.length > 99 ? "99+" : String(page.notifs.current.length)
                                color: page.style.textMuted
                                font.family: page.style.fontFamily
                                font.pixelSize: page.style.fontSizeSmall
                            }
                            StatusIcon {
                                kind: "chevron"
                                ink: page.style.textMuted
                                Layout.preferredWidth: 20; Layout.preferredHeight: 20
                            }
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 68
                    visible: !!page.player
                    radius: page.style.radiusControl
                    color: page.style.surfaceRaised
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: page.style.spaceMd
                        spacing: 12
                        ClippingRectangle {
                            Layout.preferredWidth: 42
                            Layout.preferredHeight: 42
                            radius: page.style.radiusControl
                            color: page.style.surfaceHover
                            Image {
                                id: cover
                                anchors.fill: parent
                                source: page.player?.trackArtUrl || ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready
                            }
                            StatusIcon {
                                anchors.centerIn: parent
                                width: 18; height: 18
                                visible: !cover.visible
                                kind: "music"
                                ink: page.style.textMuted
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 4
                            Text {
                                Layout.fillWidth: true
                                text: page.player?.trackTitle || page.player?.identity || "Media"
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: page.style.textPrimary
                                font.family: page.style.fontFamily
                                font.pixelSize: page.style.fontSizeBody
                                font.weight: Font.Medium
                            }
                            Text {
                                Layout.fillWidth: true
                                text: page.player?.trackArtist || page.player?.identity || ""
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: page.style.textMuted
                                font.family: page.style.fontFamily
                                font.pixelSize: page.style.fontSizeSmall
                            }
                        }
                        ChoiceButton {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 34
                            style: page.style; label: ""; iconKind: "prev"; iconSize: 16
                            tooltip: "Previous track"
                            available: page.player?.canGoPrevious ?? false
                            onTriggered: page.player?.previous()
                        }
                        ChoiceButton {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            style: page.style; label: ""; iconKind: page.player?.isPlaying ? "pause" : "play"
                            tooltip: page.player?.isPlaying ? "Pause" : "Play"
                            available: page.player?.canTogglePlaying ?? false
                            onTriggered: page.player?.togglePlaying()
                        }
                        ChoiceButton {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 34
                            style: page.style; label: ""; iconKind: "next"; iconSize: 16
                            tooltip: "Next track"
                            available: page.player?.canGoNext ?? false
                            onTriggered: page.player?.next()
                        }
                    }
                }
                // Center every row of navigation, tray and quick tools.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 4
                    color: page.style.separator
                }
                WorkspaceStrip {
                    id: navigationStrip
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: implicitHeight
                    style: page.style
                    controls: page.controls
                    searchModel: page.searchModel
                    workspaces: page.displayedWorkspaces
                    windows: page.displayedWindows
                    trayItems: page.trayItems
                    toolsComponent: Component {
                        PanelTools {
                            style: page.style
                            services: page.services
                            actions: page.actions
                        }
                    }
                    onMenuRequested: (owner, right, top) => {
                        const pos = navigationStrip.mapToItem(page, right, top);
                        page.menuRequested(owner, pos.x, pos.y);
                    }
                }
            }
        }
    }
}

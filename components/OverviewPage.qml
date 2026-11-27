pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import ".."

// Quick actions are separate from the labelled detail-navigation targets.
// Full lists and less frequent commands remain in details and global search.
ColumnLayout {
    id: page
    required property Theme style
    required property var services
    required property var actions
    required property var notifs
    required property var searchModel
    required property var trayItems
    signal menuRequested(var owner, real right, real top)
    required property var controls
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
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        implicitHeight: page.naturalHeight
        FocusFlickable {
            id: viewport
            objectName: "overview-scroll"
            anchors.fill: parent
            contentWidth: width
            contentHeight: content.implicitHeight
            followFocus: page.panelOpen
            ColumnLayout {
                id: content
                width: viewport.width
                spacing: page.style.spaceMd
                GridLayout {
                    Layout.fillWidth: true
                    columns: content.width >= 540 ? 2 : 1
                    columnSpacing: page.style.spaceMd
                    rowSpacing: page.style.spaceMd
                    GroupCard {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        style: page.style
                        contentSpacing: 0
                        ConnectivitySummary {
                            Layout.fillWidth: true
                            singleColumn: true
                            rowSpacing: 0
                            style: page.style
                            actions: page.actions
                            system: page.system
                        }
                    }
                    GroupCard {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        style: page.style
                        contentSpacing: 0
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
                }
                GroupCard {
                    Layout.fillWidth: true
                    style: page.style
                    GridLayout {
                        Layout.fillWidth: true
                        columns: content.width >= 320 ? 2 : 1
                        rowSpacing: 0
                        columnSpacing: page.style.spaceSm
                        Repeater {
                            model: [
                                {route: "appearance", title: "Appearance", icon: "appearance"},
                                {route: "wallpaper", title: "Wallpaper", icon: "app"},
                                {route: "displays", title: "Displays", icon: "window"},
                                {route: "idle", title: "Idle and lock", icon: "lock"}
                            ]
                            delegate: DeviceRow {
                                required property var modelData
                                objectName: "settings-" + modelData.route
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: 1
                                style: page.style
                                title: modelData.title
                                iconKind: modelData.icon
                                // Match the status rows above: chevrons share one right edge.
                                leftInset: page.style.spaceSm
                                rightInset: page.style.spaceXs
                                available: page.actions.available(modelData.route)
                                onTriggered: page.actions.execute(modelData.route)
                            }
                        }
                    }
                }
                DeviceRow {
                    id: notificationEntry
                    objectName: "overview-notifications"
                    Layout.fillWidth: true
                    style: page.style
                    iconKind: "bell"
                    title: page.notifs.current.length
                        ? String(page.notifs.current[0].summary || "Notification").replace(/\s+/g, " ")
                        : "No pending notifications"
                    Accessible.name: page.notifs.current.length
                        ? page.notifs.current.length + " pending notifications. Latest: " + notificationEntry.title
                        : notificationEntry.title + ". Open notification history"
                    expanded: true
                    onTriggered: page.actions.execute("notifications")
                }
                Rectangle {
                    id: mediaCard
                    readonly property int coverSize: 44
                    Layout.fillWidth: true
                    implicitHeight: mediaCard.coverSize + 2 * page.style.spaceMd
                    visible: !!page.player
                    radius: page.style.radiusControl
                    color: page.style.surfaceRaised
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: page.style.spaceMd
                        spacing: page.style.spaceMd
                        ClippingRectangle {
                            Layout.preferredWidth: mediaCard.coverSize
                            Layout.preferredHeight: mediaCard.coverSize
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
                        DeviceRow {
                            objectName: "open-media"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.fillHeight: true
                            style: page.style
                            title: page.player?.trackTitle || page.player?.identity || "Media"
                            subtitle: page.player?.trackArtist || page.player?.identity || ""
                            // The card body is the link; the transport buttons sit where a chevron would.
                            showChevron: false
                            leftInset: page.style.spaceXs
                            rightInset: page.style.spaceXs
                            onTriggered: page.actions.execute("media")
                        }
                        ChoiceButton {
                            Layout.preferredWidth: page.style.compactControlHeight
                            Layout.preferredHeight: page.style.compactControlHeight
                            style: page.style; label: ""; iconKind: "prev"; iconSize: 16
                            tooltip: "Previous track"
                            available: page.player?.canGoPrevious ?? false
                            onTriggered: page.player?.previous()
                        }
                        ChoiceButton {
                            Layout.preferredWidth: page.style.compactControlHeight
                            Layout.preferredHeight: page.style.compactControlHeight
                            style: page.style; label: ""; iconKind: page.player?.isPlaying ? "pause" : "play"
                            tooltip: page.player?.isPlaying ? "Pause" : "Play"
                            available: page.player?.canTogglePlaying ?? false
                            onTriggered: page.player?.togglePlaying()
                        }
                        ChoiceButton {
                            Layout.preferredWidth: page.style.compactControlHeight
                            Layout.preferredHeight: page.style.compactControlHeight
                            style: page.style; label: ""; iconKind: "next"; iconSize: 16
                            tooltip: "Next track"
                            available: page.player?.canGoNext ?? false
                            onTriggered: page.player?.next()
                        }
                    }
                }
                WorkspaceStrip {
                    id: navigationStrip
                    objectName: "workspace-footer"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
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

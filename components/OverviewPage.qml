pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import ".."

// Primary Super+Q hub: 2-up status medallions, 2-up thick pill sliders,
// 4-up compact settings strip, active media/notifications, and anchored footer.
ColumnLayout {
    id: page
    required property Theme style
    required property var services
    required property var actions
    required property var notifs
    property var appearance: null
    property var keyboard: null
    required property var searchModel
    required property var trayItems
    signal menuRequested(var owner, real right, real top)
    signal workspaceManageRequested(string address)
    required property var controls
    required property bool panelOpen
    signal dismissRequested
    readonly property real naturalHeight: content.implicitHeight
    readonly property bool hasFooter: navigationStrip.hasContent
    readonly property var system: services.controls
    readonly property var player: services.player
    readonly property var sink: services.sink
    readonly property int pendingCount: notifs.current.length
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
                spacing: 10

                // 1. Dual connectivity tiles with medallion toggles
                ConnectivitySummary {
                    Layout.fillWidth: true
                    singleColumn: content.width < 440
                    style: page.style
                    actions: page.actions
                    system: page.system
                }

                // 2. Dual thick-pill hardware sliders (Volume & Brightness)
                GridLayout {
                    Layout.fillWidth: true
                    columns: content.width >= 440 ? 2 : 1
                    columnSpacing: 10
                    rowSpacing: 8

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
                        onEdited: value => page.services.setBrightness(value)
                    }
                }

                // 3. 5-up quick-panels strip (5 equal pills wide, 3+2 equal pills narrow)
                Item {
                    id: settingsGrid
                    readonly property bool wideStrip: width >= 520
                    readonly property int gap: 8
                    readonly property int rowHeight: 38
                    Layout.fillWidth: true
                    implicitHeight: wideStrip ? rowHeight : rowHeight * 2 + gap

                    Repeater {
                        model: [
                            {route: "appearance", title: "Appearance", icon: "appearance"},
                            {route: "wallpaper", title: "Wallpaper", icon: "wallpaper"},
                            {route: "displays", title: "Displays", icon: "display"},
                            {route: "idle", title: "Idle", icon: "lock"},
                            {route: "session", title: "Power", icon: "power"}
                        ]
                        delegate: ChoiceButton {
                            id: settingPill
                            required property var modelData
                            required property int index
                            readonly property int countInRow: settingsGrid.wideStrip ? 5 : (index < 3 ? 3 : 2)
                            readonly property int colInRow: settingsGrid.wideStrip ? index : (index < 3 ? index : index - 3)
                            readonly property real cellWidth: (settingsGrid.width - (countInRow - 1) * settingsGrid.gap) / countInRow
                            objectName: modelData.route === "session" ? "power-menu-button" : "settings-" + modelData.route
                            x: Math.round(colInRow * (cellWidth + settingsGrid.gap))
                            y: settingsGrid.wideStrip || index < 3 ? 0 : settingsGrid.rowHeight + settingsGrid.gap
                            width: colInRow === countInRow - 1
                                ? Math.max(0, settingsGrid.width - x)
                                : Math.max(0, Math.round((colInRow + 1) * (cellWidth + settingsGrid.gap) - settingsGrid.gap) - x)
                            height: settingsGrid.rowHeight
                            style: page.style
                            cardFilled: true
                            label: modelData.title
                            iconKind: modelData.icon
                            iconSize: 16
                            textSize: page.style.fontSizeLabel
                            available: page.actions.available(modelData.route)
                            onTriggered: page.actions.execute(modelData.route)
                        }
                    }
                }

                // 4. Active media card (52px tile matching connectivity proportions & typography)
                ClippingRectangle {
                    id: mediaCard
                    readonly property int coverSize: 36
                    readonly property bool hasTimeline: !!page.player?.positionSupported
                        && !!page.player?.lengthSupported && (page.player?.length ?? 0) > 0
                    property int progressTick: 0
                    readonly property real progressRatio: {
                        const sample = progressTick;
                        return hasTimeline ? Math.max(0, Math.min(1, page.player.position / page.player.length)) : 0;
                    }
                    readonly property string mediaTitle: page.player?.trackTitle || page.player?.identity || "Media"
                    readonly property string mediaSubtitle: {
                        const artist = page.player?.trackArtist || "";
                        const identity = page.player?.identity || "";
                        if (artist && identity && artist.toLowerCase() !== identity.toLowerCase())
                            return artist + " · " + identity;
                        if (artist) return artist;
                        if (identity && identity !== mediaTitle) return identity;
                        return page.player?.isPlaying ? "Playing" : "Paused";
                    }
                    Layout.fillWidth: true
                    implicitHeight: 52
                    visible: !!page.player
                    radius: page.style.radiusCard
                    color: openMediaButton.hovered ? page.style.surfaceHover : page.style.cardSurface

                    Timer {
                        interval: 1000
                        running: page.panelOpen && mediaCard.visible && mediaCard.hasTimeline && !!page.player?.isPlaying
                        repeat: true
                        onTriggered: mediaCard.progressTick++
                    }

                    RowLayout {
                        anchors.fill: parent
                        spacing: 0

                        ChoiceButton {
                            id: openMediaButton
                            objectName: "open-media"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.fillHeight: true
                            style: page.style
                            color: "transparent"
                            label: ""
                            tooltip: "Open media player controls"
                            Accessible.name: mediaCard.mediaTitle + (mediaCard.mediaSubtitle ? ", " + mediaCard.mediaSubtitle : "")
                            onTriggered: page.actions.execute("media")

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 10
                                spacing: 10

                                ClippingRectangle {
                                    Layout.preferredWidth: mediaCard.coverSize
                                    Layout.preferredHeight: mediaCard.coverSize
                                    radius: page.style.radiusSmall
                                    color: page.style.controlSurface

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
                                        width: 16
                                        height: 16
                                        visible: !cover.visible
                                        kind: "music"
                                        ink: page.player?.isPlaying ? page.style.accent : page.style.textMuted
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: mediaCard.mediaTitle
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        color: page.style.textPrimary
                                        font.family: page.style.fontFamily
                                        font.pixelSize: page.style.fontSizeSmall
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        visible: mediaCard.mediaSubtitle !== ""
                                        text: mediaCard.mediaSubtitle
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        color: page.style.textMuted
                                        font.family: page.style.fontFamily
                                        font.pixelSize: page.style.fontSizeCaption
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 24
                            color: page.style.separator
                            opacity: 0.8
                        }

                        Row {
                            Layout.leftMargin: 6
                            Layout.rightMargin: 6
                            spacing: 2

                            ChoiceButton {
                                width: 30
                                height: 32
                                style: page.style
                                label: ""
                                iconKind: "prev"
                                iconSize: 15
                                tooltip: "Previous track"
                                available: page.player?.canGoPrevious ?? false
                                onTriggered: page.player?.previous()
                            }

                            ChoiceButton {
                                width: 32
                                height: 32
                                style: page.style
                                tone: "toggle"
                                selected: page.player?.isPlaying ?? false
                                filled: !(page.player?.isPlaying ?? false)
                                label: ""
                                iconKind: page.player?.isPlaying ? "pause" : "play"
                                iconSize: 15
                                tooltip: page.player?.isPlaying ? "Pause" : "Play"
                                available: page.player?.canTogglePlaying ?? false
                                onTriggered: page.player?.togglePlaying()
                            }

                            ChoiceButton {
                                width: 30
                                height: 32
                                style: page.style
                                label: ""
                                iconKind: "next"
                                iconSize: 15
                                tooltip: "Next track"
                                available: page.player?.canGoNext ?? false
                                onTriggered: page.player?.next()
                            }
                        }
                    }

                    Rectangle {
                        visible: mediaCard.hasTimeline && mediaCard.progressRatio > 0
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        width: Math.round(parent.width * mediaCard.progressRatio)
                        height: 2
                        color: page.player?.isPlaying ? page.style.accent : page.style.outline
                        opacity: page.player?.isPlaying ? 0.55 : 0.35
                    }
                }

                // 5. Compact notification banner row with unread count pill
                ChoiceButton {
                    id: notificationEntry
                    objectName: "overview-notifications"
                    Layout.fillWidth: true
                    Layout.preferredHeight: page.pendingCount > 0 ? 40 : 36
                    style: page.style
                    cardFilled: true
                    label: ""
                    readonly property string summaryText: page.pendingCount > 0
                        ? String(page.notifs.current[0].summary || "Notification").replace(/\s+/g, " ")
                        : "Notifications"
                    Accessible.name: page.pendingCount > 0
                        ? page.pendingCount + " pending notifications. Latest: " + notificationEntry.summaryText
                        : "No pending notifications. Open notification history"
                    onTriggered: page.actions.execute("notifications")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 8

                        StatusIcon {
                            kind: page.notifs.doNotDisturb ? "bell-off" : "bell"
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16
                            ink: page.notifs.doNotDisturb ? page.style.accentWarm
                                : page.pendingCount > 0 ? page.style.accent : page.style.textMuted
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: notificationEntry.summaryText
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: page.pendingCount > 0 ? page.style.textPrimary : page.style.textMuted
                            font.family: page.style.fontFamily
                            font.pixelSize: page.style.fontSizeSmall
                            font.weight: page.pendingCount > 0 ? Font.Medium : Font.Normal
                        }

                        Rectangle {
                            visible: page.pendingCount > 0
                            Layout.preferredHeight: 18
                            Layout.preferredWidth: Math.max(18, countLabel.implicitWidth + 10)
                            radius: 9
                            color: page.style.surfaceSelected
                            Text {
                                id: countLabel
                                anchors.centerIn: parent
                                text: String(page.pendingCount)
                                color: page.style.accent
                                font.family: page.style.fontFamily
                                font.pixelSize: page.style.fontSizeCaption
                                font.weight: Font.Bold
                            }
                        }

                        Text {
                            visible: page.pendingCount === 0
                            text: page.notifs.doNotDisturb ? "Paused" : "Quiet"
                            color: page.notifs.doNotDisturb ? page.style.accentWarm : page.style.textMuted
                            font.family: page.style.fontFamily
                            font.pixelSize: page.style.fontSizeCaption
                        }

                        StatusIcon {
                            kind: "chevron"
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16
                            ink: page.style.textMuted
                            opacity: 0.7
                        }
                    }
                }

                // 6. Centered dynamic status bar (workspaces · tray · active state)
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
                            notifs: page.notifs
                            appearance: page.appearance
                            keyboard: page.keyboard
                        }
                    }
                    onMenuRequested: (owner, right, top) => {
                        const pos = navigationStrip.mapToItem(page, right, top);
                        page.menuRequested(owner, pos.x, pos.y);
                    }
                    onWorkspaceManageRequested: address => page.workspaceManageRequested(address)
                }
            }
        }
    }
}

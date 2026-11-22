pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Widgets
import ".."

Rectangle {
    id: detail
    required property Theme style
    required property var appearance
    property var displays: null
    property var idlePreferences: null
    required property var services
    required property var actions
    required property var notifs
    required property var wallpaper
    property bool detached: false
    signal detachRequested()
    readonly property bool dialogOpen: wallpaperLoader.item?.dialogOpen ?? false
    readonly property var system: services.controls
    required property string section
    property string audioTab: "Output"
    readonly property bool audioInput: audioTab === "Microphone"
    readonly property bool mixerVisible: panelOpen && section === "audio" && audioTab === "Mixer"
    readonly property string historyQuery: historyFilter.text.trim().toLowerCase()
    property bool showHistory: false
    // Keep the current page through its exit animation, then release delegates.
    // Never instantiate unrelated detail lists behind the selected section.
    property bool retainContent: false
    readonly property bool renderContent: panelOpen || retainContent
    readonly property var notificationEntries: renderContent && isNotifs
        ? (showHistory ? notifs.history.filter(entry => !historyQuery ||
            [entry.appName, entry.desktopEntry, entry.summary, entry.body].some(value =>
                String(value || "").toLowerCase().includes(historyQuery))) : notifs.current) : []
    property bool panelOpen: visible
    signal dismissRequested()
    signal closePanelRequested()
    readonly property bool isNotifs: section === "notifications"
    readonly property string title: section === "session" ? "Power and session" : section === "appearance" ? "Appearance"
        : section === "displays" ? "Displays"
        : section === "idle" ? "Idle and lock"
        : section === "wallpaper" ? "Wallpaper" : section === "wifi" ? "Wi-Fi"
        : section === "bluetooth" ? "Bluetooth"
        : section === "media" ? "Media player"
        : detail.isNotifs ? "Notifications"
        : "Audio devices"
    readonly property string subtitle: section === "session" ? "Lock your screen or leave this session" : section === "appearance" ? "Light, dark and sunrise-to-sunset scheduling"
        : section === "displays" ? "Arrangement, resolution and scale"
        : section === "idle" ? "Automatic dimming, locking and display off"
        : section === "wallpaper" ? "Desktop and lock-screen background" : section === "wifi" ? "Nearby networks · connect & manage"
        : section === "bluetooth" ? "Devices · discover, pair & connect"
        : section === "media" ? "Players in this session"
        : detail.isNotifs ? (detail.showHistory ? "Saved notifications · clearing history also dismisses pending entries"
            : "Pending notifications · cleared entries remain in history")
        : "Playback streams and default devices"
    readonly property bool radioEnabled: section === "wifi" ? system.wifiEnabled : system.bluetoothEnabled
    readonly property var rows: renderContent && section === "audio" && audioTab !== "Mixer"
        ? (audioInput ? services.audioInputs : services.audioOutputs) : []
    onSectionChanged: { audioTab = "Output"; showHistory = false; viewport.contentY = 0; }
    readonly property real naturalHeight: detailHeader.Layout.preferredHeight + 1 + 2 * style.spaceMd + content.implicitHeight
        + (isNotifs ? notificationToolbar.implicitHeight + style.spaceMd : 0)
        + (settingsFooter.visible ? settingsFooter.implicitHeight + style.spaceMd : 0)
    implicitWidth: 380
    color: detached ? style.panelSurface : "transparent"
    focus: visible
    Keys.onEscapePressed: dismissRequested()
    Shortcut {
        sequence: "Ctrl+Shift+D"
        context: Qt.WindowShortcut
        enabled: detail.panelOpen && !detail.detached && detail.section !== "session" && !detail.dialogOpen
        onActivated: detail.detachRequested()
    }
    MouseArea { anchors.fill: parent }

    ColumnLayout {
        anchors.fill: parent
        spacing: detail.style.spaceMd
        DetailHeader {
            id: detailHeader
            style: detail.style
            title: detail.title
            subtitle: detail.subtitle
            showSubtitle: ["appearance", "displays", "idle", "wallpaper"].includes(detail.section)
            backTooltip: detail.detached ? "Close window" : "Back to overview"
            backIcon: detail.detached ? "close" : "back"
            onBackRequested: detail.dismissRequested()
            actions: [
                ChoiceButton {
                    visible: detail.section === "wifi" || detail.section === "bluetooth"
                    Layout.preferredWidth: 72
                    compact: true
                    style: detail.style
                    label: detail.radioEnabled ? "On" : "Off"
                    selected: detail.radioEnabled
                    tone: "toggle"
                    available: detail.actions.available(detail.section + "-toggle")
                    onTriggered: detail.actions.execute(detail.section + "-toggle")
                },
                ChoiceButton {
                    objectName: "notification-clear-all"
                    Layout.preferredWidth: detail.showHistory ? 96 : 72
                    compact: true
                    visible: detail.isNotifs && !(detail.showHistory && detail.historyQuery)
                    style: detail.style
                    label: detail.showHistory ? "Clear history" : "Clear all"
                    available: detail.notificationEntries.length > 0
                    onTriggered: {
                        if (detail.showHistory) detail.notifs.clearHistory();
                        else detail.notifs.clearCurrent();
                    }
                },
                ChoiceButton {
                    objectName: "notification-quiet"
                    visible: detail.isNotifs
                    compact: true
                    tone: "toggle"
                    iconKind: selected ? "bell-off" : "bell"
                    Accessible.checkable: true
                    Accessible.checked: selected
                    style: detail.style
                    label: ""
                    selected: detail.notifs.doNotDisturb
                    available: detail.notifs.quietReady
                    tooltip: detail.notifs.quietError || (detail.notifs.doNotDisturb
                        ? "Resume banners · paused until " + Qt.formatTime(new Date(detail.notifs.quietUntil), "hh:mm")
                            + " · Critical alerts still appear"
                        : "Pause banners for one hour · Critical alerts still appear")
                    onTriggered: detail.actions.execute(detail.notifs.doNotDisturb ? "notifications-resume" : "notifications-pause")
                },
                ChoiceButton {
                    objectName: "detach-page"
                    visible: !detail.detached && detail.section !== "session"
                    compact: true
                    style: detail.style
                    label: ""
                    iconKind: "window"
                    tooltip: "Detach into a window (Ctrl+Shift+D)"
                    onTriggered: detail.detachRequested()
                }
            ]
        }
        RowLayout {
            id: notificationToolbar
            Layout.fillWidth: true
            visible: detail.isNotifs
            spacing: detail.style.spaceSm
            ChoiceButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                filled: true
                style: detail.style
                label: "Pending · " + detail.notifs.current.length
                selected: !detail.showHistory
                onTriggered: { detail.showHistory = false; viewport.contentY = 0; }
            }
            ChoiceButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                filled: true
                style: detail.style
                objectName: "notification-history"
                label: "History · " + detail.notifs.history.length
                selected: detail.showHistory
                onTriggered: { detail.showHistory = true; viewport.contentY = 0; }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: detail.style.separator
        }
        ClippingRectangle {
            id: scrollFrame
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            implicitHeight: content.implicitHeight
            radius: detail.style.radiusCard
            color: "transparent"
            FocusFlickable {
                id: viewport
                objectName: "detail-scroll"
                anchors.fill: parent
                contentWidth: width
                contentHeight: content.implicitHeight
                followFocus: detail.panelOpen
                ScrollBar.vertical: ScrollBar {
                    id: scrollBar
                    // Keep the content aligned with the header. The scroll track
                    // lives in the panel's outer inset, not in the content column.
                    parent: detail
                    x: detail.width + detail.style.spaceXs
                    y: scrollFrame.y
                    width: 8
                    height: viewport.height
                    padding: 2
                    policy: ScrollBar.AsNeeded
                    // A custom contentItem must provide its own AsNeeded visibility.
                    visible: viewport.contentHeight > viewport.height + 1
                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: 2
                        color: detail.style.textMuted
                        opacity: scrollBar.pressed ? 0.8 : 0.45
                    }
                }
                ColumnLayout {
                    id: content
                    width: viewport.width
                    spacing: detail.style.spaceMd
                    RowLayout {
                        Layout.fillWidth: true
                        visible: detail.section === "audio"
                        spacing: detail.style.spaceSm
                        Repeater {
                            model: ["Output", "Microphone", "Mixer"]
                            delegate: ChoiceButton {
                                required property string modelData
                                objectName: "audio-" + modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 36
                                style: detail.style
                                label: modelData
                                selected: detail.audioTab === modelData
                                onTriggered: { detail.audioTab = modelData; viewport.contentY = 0; }
                            }
                        }
                    }
                    Loader {
                        Layout.fillWidth: true
                        active: detail.mixerVisible
                        visible: active
                        sourceComponent: PlaybackMixer { style: detail.style; streams: detail.services.playbackStreams }
                    }
                    Loader {
                        Layout.fillWidth: true
                        active: detail.renderContent && detail.section === "media"
                        visible: active
                        sourceComponent: MediaPane { style: detail.style; services: detail.services }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: detail.section === "audio" && detail.audioTab !== "Mixer"
                        spacing: detail.style.spaceXs
                        Repeater {
                            model: detail.rows
                            delegate: DeviceRow {
                                required property var modelData
                                Layout.fillWidth: true
                                style: detail.style
                                title: modelData.description || modelData.name
                                selected: modelData === (detail.audioInput ? detail.services.source : detail.services.sink)
                                subtitle: selected ? "Current device" : ""
                                onTriggered: detail.services.selectAudioDevice(modelData, detail.audioInput)
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 80
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            visible: detail.rows.length === 0
                            text: "No audio devices available"
                            color: detail.style.textMuted
                            font.family: detail.style.fontFamily
                            font.pixelSize: detail.style.fontSizeBody
                        }
                    }
                    Loader {
                        id: wallpaperLoader
                        Layout.fillWidth: true
                        active: detail.renderContent && detail.section === "wallpaper"
                        visible: active
                        sourceComponent: WallpaperPicker { style: detail.style; wallpaper: detail.wallpaper; detached: detail.detached }
                    }
                    Loader {
                        Layout.fillWidth: true
                        active: detail.renderContent && detail.section === "appearance"
                        visible: active
                        sourceComponent: Component {
                            AppearancePane { style: detail.style; appearance: detail.appearance }
                        }
                    }
                    Loader {
                        id: displayLoader
                        Layout.fillWidth: true
                        active: detail.renderContent && detail.section === "displays" && !!detail.displays
                        visible: active
                        sourceComponent: DisplaysPane {
                            style: detail.style
                            service: detail.displays
                            footerHost: settingsFooter
                            detachedBodyHeight: detail.detached ? viewport.height : 0
                        }
                    }
                    Loader {
                        id: idleLoader
                        Layout.fillWidth: true
                        active: detail.renderContent && detail.section === "idle" && !!detail.idlePreferences
                        visible: active
                        sourceComponent: IdlePane { style: detail.style; preferences: detail.idlePreferences; services: detail.services; footerHost: settingsFooter }
                    }
                    Loader {
                        Layout.fillWidth: true
                        active: detail.renderContent && detail.section === "session"
                        visible: active
                        sourceComponent: Component {
                            PowerPane { style: detail.style; services: detail.services; actions: detail.actions; onCloseRequested: detail.closePanelRequested() }
                        }
                    }
                    ConnectivityPane {
                        Layout.fillWidth: true
                        visible: detail.section === "wifi" || detail.section === "bluetooth"
                        active: detail.panelOpen && visible
                        retainContent: detail.renderContent && visible
                        section: detail.section
                        style: detail.style
                        services: detail.services
                        onRevealRequested: viewport.contentY = 0
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: detail.isNotifs
                        spacing: detail.style.spaceXs
                        ConnectionField {
                            id: historyFilter
                            objectName: detail.isNotifs ? "notification-filter" : ""
                            Layout.fillWidth: true
                            visible: detail.showHistory
                            style: detail.style
                            placeholderText: "Filter by application or notification text"
                            Accessible.name: placeholderText
                            onTextChanged: viewport.contentY = 0
                        }
                        Repeater {
                            model: detail.notificationEntries
                            delegate: NotificationRow {
                                required property int index
                                required property var modelData
                                Layout.fillWidth: true
                                style: detail.style
                                objectName: "notification-record-" + modelData.recordKey
                                entry: modelData
                                compact: false
                                actions: detail.notifs.entryActions(entry)
                                activationLabel: detail.notifs.activationLabel(entry)
                                onActivated: { if (detail.notifs.activateEntry(entry)) detail.closePanelRequested(); }
                                onActionRequested: action => { if (detail.notifs.invokeEntryAction(entry, action)) detail.closePanelRequested(); }
                                onTriggered: {
                                    if (detail.showHistory) detail.notifs.removeHistory(detail.notifs.history.findIndex(record => record.recordKey === entry.recordKey));
                                    else detail.notifs.removeCurrent(index);
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 80
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            visible: detail.notificationEntries.length === 0
                            text: detail.showHistory && detail.historyQuery ? "No matching notifications" : detail.showHistory ? "No saved notifications" : "No pending notifications"
                            color: detail.style.textMuted
                            font.family: detail.style.fontFamily
                            font.pixelSize: detail.style.fontSizeBody
                        }
                    }

                }
            }
        }
        // Confirm and revert must stay reachable even if the display form scrolls.
        Item {
            id: settingsFooter
            Layout.fillWidth: true
            readonly property var page: displayLoader.item ?? idleLoader.item
            visible: page?.footerVisible ?? false
            implicitHeight: page?.footerHeight ?? 0
        }
    }
}

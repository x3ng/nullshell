pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import Quickshell.Widgets
import ".."

Rectangle {
    id: detail
    required property Theme style
    required property var appearance
    required property var services
    required property var actions
    required property var notifs
    required property var wallpaper
    property bool detached: false
    signal detachRequested()
    readonly property bool dialogOpen: wallpaperLoader.item?.dialogOpen ?? false
    readonly property var system: services.controls
    required property string section
    property bool audioInput: false
    property bool showHistory: false
    // Keep the current page through its exit animation, then release delegates.
    // Never instantiate unrelated detail lists behind the selected section.
    property bool retainContent: false
    readonly property bool renderContent: panelOpen || retainContent
    readonly property var notificationEntries: renderContent && isNotifs
        ? (showHistory ? notifs.history : notifs.current) : []
    property bool panelOpen: visible
    signal dismissRequested()
    signal closePanelRequested()
    readonly property bool isNotifs: section === "notifications"
    readonly property string title: section === "session" ? "Power and session" : section === "appearance" ? "Appearance"
        : section === "wallpaper" ? "Wallpaper" : section === "wifi" ? "Wi-Fi"
        : section === "bluetooth" ? "Bluetooth"
        : detail.isNotifs ? "Notifications"
        : "Audio devices"
    readonly property string subtitle: section === "session" ? "Lock your screen or leave this session" : section === "appearance" ? "Light, dark and sunrise-to-sunset scheduling"
        : section === "wallpaper" ? "Desktop and lock-screen background" : section === "wifi" ? "Nearby networks · connect & manage"
        : section === "bluetooth" ? "Devices · discover, pair & connect"
        : detail.isNotifs ? (detail.showHistory ? "Saved notifications · clearing history also dismisses pending entries"
            : "Pending notifications · cleared entries remain in history")
        : "Choose your default device"
    readonly property bool radioEnabled: section === "wifi" ? system.wifiEnabled : system.bluetoothEnabled
    readonly property var rows: renderContent && section === "audio"
        ? (audioInput ? services.audioInputs : services.audioOutputs) : []
    onSectionChanged: { audioInput = false; showHistory = false; viewport.contentY = 0; }
    readonly property real naturalHeight: detailHeader.implicitHeight + 10 + content.implicitHeight
        + (isNotifs ? notificationToolbar.implicitHeight + 10 : 0)
    implicitWidth: 380
    color: detached ? style.panelSurface : "transparent"
    focus: visible
    Keys.onEscapePressed: dismissRequested()
    function revealFocus() {
        const item = detail.Window.window?.activeFocusItem;
        if (!item) return;
        let ancestor = item;
        while (ancestor && ancestor !== content) ancestor = ancestor.parent;
        if (!ancestor) return;
        const point = item.mapToItem(viewport, 0, 0);
        if (point.y < 0) viewport.contentY += point.y;
        else if (point.y + item.height > viewport.height)
            viewport.contentY += point.y + item.height - viewport.height;
        viewport.contentY = Math.max(0, Math.min(viewport.contentY, viewport.contentHeight - viewport.height));
    }
    Connections {
        target: detail.Window.window
        function onActiveFocusItemChanged() { Qt.callLater(detail.revealFocus); }
    }
    Shortcut {
        sequence: "Ctrl+Shift+D"
        context: Qt.WindowShortcut
        enabled: detail.panelOpen && !detail.detached && detail.section !== "session" && !detail.dialogOpen
        onActivated: detail.detachRequested()
    }
    MouseArea { anchors.fill: parent }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        DetailHeader {
            id: detailHeader
            style: detail.style
            title: detail.title
            subtitle: detail.subtitle
            backTooltip: detail.detached ? "Close window" : "Back to overview"
            backIcon: detail.detached ? "close" : "back"
            onBackRequested: detail.dismissRequested()
            actions: [
                ChoiceButton {
                    objectName: "detach-page"
                    visible: !detail.detached && detail.section !== "session"
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    style: detail.style
                    label: ""
                    iconKind: "window"
                    tooltip: "Detach into a window (Ctrl+Shift+D)"
                    onTriggered: detail.detachRequested()
                },
                ChoiceButton {
                    visible: detail.section === "wifi" || detail.section === "bluetooth"
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 30
                    style: detail.style
                    label: detail.radioEnabled ? "On" : "Off"
                    selected: detail.radioEnabled
                    tone: "toggle"
                    available: detail.actions.available(detail.section + "-toggle")
                    onTriggered: detail.actions.execute(detail.section + "-toggle")
                },
            ChoiceButton {
                objectName: "notification-clear-all"
                Layout.preferredWidth: 112
                Layout.preferredHeight: 30
                visible: detail.isNotifs
                style: detail.style
                label: detail.showHistory ? "Clear history" : "Clear all"
                available: detail.notificationEntries.length > 0
                onTriggered: {
                    if (detail.showHistory) detail.notifs.clearHistory();
                    else detail.notifs.clearCurrent();
                }
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
                Layout.preferredHeight: 36
                filled: true
                style: detail.style
                label: "Pending · " + detail.notifs.current.length
                selected: !detail.showHistory
                onTriggered: { detail.showHistory = false; viewport.contentY = 0; }
            }
            ChoiceButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 36
                filled: true
                style: detail.style
                label: "History · " + detail.notifs.history.length
                selected: detail.showHistory
                onTriggered: { detail.showHistory = true; viewport.contentY = 0; }
            }

        }
        ClippingRectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            implicitHeight: content.implicitHeight
            radius: detail.style.radiusCard
            color: "transparent"
            Flickable {
                id: viewport
                objectName: "detail-scroll"
                anchors.fill: parent
                contentWidth: width
                contentHeight: content.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    id: scrollBar
                    policy: ScrollBar.AsNeeded
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
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        visible: detail.section === "audio"
                        spacing: detail.style.spaceSm
                        ChoiceButton {
                            Layout.fillWidth: true
                            style: detail.style
                            label: "Output"
                            selected: !detail.audioInput
                            onTriggered: { detail.audioInput = false; viewport.contentY = 0; }
                        }
                        ChoiceButton {
                            Layout.fillWidth: true
                            style: detail.style
                            label: "Microphone"
                            selected: detail.audioInput
                            onTriggered: { detail.audioInput = true; viewport.contentY = 0; }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: detail.style.separator
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: detail.section === "audio"
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
                        sourceComponent: WallpaperPicker { style: detail.style; wallpaper: detail.wallpaper }
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
                        Layout.fillWidth: true
                        active: detail.renderContent && detail.section === "session"
                        visible: active
                        sourceComponent: Component {
                            PowerPane { style: detail.style; actions: detail.actions; onCloseRequested: detail.closePanelRequested() }
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
                        Repeater {
                            model: detail.notificationEntries
                            delegate: NotificationRow {
                                required property int index
                                required property var modelData
                                Layout.fillWidth: true
                                style: detail.style
                                entry: modelData
                                compact: false
                                actions: detail.notifs.entryActions(entry)
                                activationLabel: detail.notifs.activationLabel(entry)
                                onActivated: { if (detail.notifs.activateEntry(entry)) detail.closePanelRequested(); }
                                onActionRequested: action => { if (detail.notifs.invokeEntryAction(entry, action)) detail.closePanelRequested(); }
                                onTriggered: {
                                    if (detail.showHistory) detail.notifs.removeHistory(index);
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
                            text: detail.showHistory ? "No saved notifications" : "No pending notifications"
                            color: detail.style.textMuted
                            font.family: detail.style.fontFamily
                            font.pixelSize: detail.style.fontSizeBody
                        }
                    }

                }
            }
        }
    }
}

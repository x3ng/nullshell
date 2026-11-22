pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import ".."

// The Loader moves between surfaces; drafts and focusable controls are not copied.
Item {
    id: host
    required property var panel
    readonly property var sections: ["wifi", "bluetooth", "audio", "media", "notifications", "appearance", "displays", "idle", "wallpaper", "session"]
    property int revision: 0
    readonly property real naturalHeight: currentPage()?.naturalHeight ?? 0
    readonly property bool dialogOpen: currentPage()?.dialogOpen ?? false
    function slot(section) {
        for (let i = 0; i < pages.count; i++) {
            const entry = pages.itemAt(i);
            if (entry && entry.modelData === section) return entry;
        }
        return null;
    }
    function currentPage() { return slot(panel.controlSection)?.loader.item ?? null; }
    function isDetached(section) { const version = revision; return slot(section)?.detached ?? false; }
    function focusDetached(section) {
        const entry = slot(section);
        if (!entry?.detached) return false;
        Qt.callLater(() => {
            if (!entry.detached) return;
            entry.window.raise(); entry.window.requestActivate();
            // Wayland may ignore QWindow activation without an input token.
            // Use the same native toplevel API as desktop window navigation.
            const matches = ToplevelManager.toplevels.values.filter(window =>
                window.appId === Quickshell.appId && window.title === entry.window.title);
            if (matches.length === 1) {
                matches[0].minimized = false;
                matches[0].activate();
            }
            entry.loader.item?.forceActiveFocus();
        });
        return true;
    }
    function closeDetached(section) { slot(section)?.window.close(); }
    function pageItem(section) { return slot(section)?.loader.item ?? null; }
    Repeater {
        id: pages
        model: host.sections
        delegate: Item {
            id: entry
            required property string modelData
            anchors.fill: parent
            property bool detached: false
            readonly property bool selected: host.panel.open && host.panel.controlSection === modelData
            readonly property bool displayEditor: modelData === "displays"
            property alias loader: contentLoader
            property alias window: floating
            onDetachedChanged: host.revision++
            Window {
                id: floating
                transientParent: null
                title: (contentLoader.item?.title ?? "Settings") + " · " + host.panel.windowTitleSuffix
                width: 660
                height: 560
                minimumWidth: 420
                minimumHeight: 320
                color: host.panel.style.panelSurface
                visible: entry.detached
                onClosing: entry.detached = false
                Shortcut {
                    sequence: "Escape"
                    context: Qt.WindowShortcut
                    enabled: entry.detached
                    onActivated: floating.close()
                }
            }
            Loader {
                id: contentLoader
                parent: entry.detached ? floating.contentItem : entry
                anchors.fill: parent
                anchors.margins: entry.detached ? host.panel.style.panelPadding : 0
                active: entry.detached || entry.selected
                visible: active
                sourceComponent: ControlDetails {
                    style: host.panel.style
                    appearance: host.panel.appearance
                    displays: host.panel.displays
                    idlePreferences: host.panel.idlePreferences
                    services: host.panel.services
                    actions: host.panel.actions
                    notifs: host.panel.notifs
                    wallpaper: host.panel.wallpaper
                    section: entry.modelData
                    detached: entry.detached
                    panelOpen: entry.detached || entry.selected
                    onDetachRequested: {
                        if (entry.displayEditor) {
                            const screen = host.panel.screen ?? floating.screen;
                            floating.width = Math.max(floating.minimumWidth, Math.min(960, screen.width - 64));
                            floating.height = Math.max(floating.minimumHeight, Math.min(640, screen.height - 64));
                        }
                        entry.detached = true;
                        host.panel.dismiss();
                        host.panel.returnToHome();
                        Qt.callLater(() => {
                            if (!entry.detached) return;
                            if (!entry.displayEditor)
                                floating.height = Math.max(floating.minimumHeight, Math.min(
                                    host.panel.style.maximumPanelHeight,
                                    floating.screen.height - 64,
                                    contentLoader.item.naturalHeight + 2 * host.panel.style.panelPadding));
                            floating.raise(); floating.requestActivate();
                            contentLoader.item?.forceActiveFocus();
                        });
                    }
                    onDismissRequested: {
                        if (entry.detached) floating.close();
                        else host.panel.returnToHome();
                    }
                    onClosePanelRequested: {
                        if (entry.detached) floating.close();
                        else host.panel.dismiss();
                    }
                    Keys.onPressed: event => { if (!entry.detached) host.panel.handleKey(event); }
                }
            }
        }
    }
}

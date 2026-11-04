pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    required property var wallpaper
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: background
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell:wallpaper"
            mask: Region {}
            color: "#191b1f"
            WallpaperImage {
                anchors.fill: parent
                source: root.wallpaper.urlFor(root.wallpaper.entryFor(background.screen.name).path)
                fit: root.wallpaper.entryFor(background.screen.name).fit
            }
        }
    }
}

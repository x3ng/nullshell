pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

Scope {
    id: state
    // Use the native IPC snapshot. No second query process or independent cache.
    readonly property var layouts: {
        const result = {};
        for (const workspace of Hyprland.workspaces.values) {
            const layout = workspace.lastIpcObject.tiledLayout;
            if (workspace.address && typeof layout === "string") result[workspace.address] = layout;
        }
        return result;
    }

    function label(workspaceAddress) {
        const layout = layouts[workspaceAddress];
        return layout ? layout.toUpperCase() : "—";
    }

    function marker(workspaceAddress) {
        const layout = layouts[workspaceAddress];
        return ({dwindle: "D", master: "M", scrolling: "S", monocle: "O"})[layout]
            ?? (layout ? layout.slice(0, 1).toUpperCase() : "—");
    }

    function refresh() {
        if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) refreshDelay.restart();
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Native focusedWorkspace names the regular workspace. Refresh the
            // monitor snapshot to observe the visible special workspace too.
            if (event.name === "activespecialv2") Hyprland.refreshMonitors();
            if (event.name === "configreloaded" || event.name === "workspacev2"
                || event.name === "activespecialv2" || event.name === "createworkspacev2"
                || event.name === "destroyworkspacev2" || event.name === "renameworkspace"
                || event.name === "changeworkspaceid" || event.name === "moveworkspacev2")
                state.refresh();
        }
    }

    // Let native initialization populate the model; an eager refresh here can
    // race its first query. Later requests coalesce after events/panel actions.
    // Hyprland 0.57 has no tiled-layout change event, so opening the panel also
    // requests a snapshot. This is a single-shot debounce, not layout polling.
    Timer { id: refreshDelay; interval: 40; onTriggered: Hyprland.refreshWorkspaces() }
}

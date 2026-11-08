import QtQuick
import QtQml.Models
import Quickshell
import Qt.labs.folderlistmodel
import Quickshell.Io

Item {
    id: root
    property var sessions: []
    property string selectedId: ""
    property string preferredId: ""
    readonly property var current: sessions.find(entry => entry.id === selectedId) ?? null
    property var loadedPaths: ({})

    onPreferredIdChanged: {
        if (!selectionTouched && sessions.some(session => session.id === preferredId))
            selectedId = preferredId;
    }

    function parseExec(value) {
        const args = [];
        let token = "";
        let quoted = false;
        let escaped = false;
        for (const char of value) {
            if (escaped) {
                token += char;
                escaped = false;
            } else if (char === "\\") {
                escaped = true;
            } else if (char === '"') {
                quoted = !quoted;
            } else if (/\s/.test(char) && !quoted) {
                if (token.length) args.push(token);
                token = "";
            } else {
                token += char;
            }
        }
        if (token.length) args.push(token);
        // Desktop-entry field codes are for application launchers, not sessions.
        return args.filter(arg => !/^%[a-zA-Z]$/.test(arg));
    }

    function addFile(path, contents) {
        const fields = {};
        let inEntry = false;
        for (const line of contents.split(/\r?\n/)) {
            if (line.startsWith("[")) {
                inEntry = line.trim() === "[Desktop Entry]";
                continue;
            }
            if (!inEntry) continue;
            const separator = line.indexOf("=");
            if (separator <= 0) continue;
            fields[line.slice(0, separator)] = line.slice(separator + 1).trim();
        }
        if (fields.Hidden === "true" || fields.NoDisplay === "true") return;
        if (!fields.Name || !fields.Exec) return;
        const args = parseExec(fields.Exec);
        if (args.length === 0) return;
        const id = path.slice(path.lastIndexOf("/") + 1);
        const entry = {
            id: id,
            name: fields.Name,
            args: args,
            desktopNames: fields.DesktopNames || ""
        };
        const updated = sessions.filter(session => session.id !== id).concat([entry]);
        updated.sort((a, b) => a.name.localeCompare(b.name));
        sessions = updated;
        if (!selectionTouched && updated.some(session => session.id === preferredId)) {
            selectedId = preferredId;
        } else if (!selectedId || !updated.some(session => session.id === selectedId)) {
            selectedId = updated.some(session => session.id === "hyprland-uwsm.desktop")
                ? "hyprland-uwsm.desktop" : updated[0].id;
        } else if (selectedId === "hyprland.desktop"
                   && updated.some(session => session.id === "hyprland-uwsm.desktop")
                   && !selectionTouched) {
            selectedId = "hyprland-uwsm.desktop";
        }
    }

    property bool selectionTouched: false
    function choose(id) {
        if (sessions.some(session => session.id === id)) {
            selectedId = id;
            selectionTouched = true;
        }
    }

    Component {
        id: desktopReader
        FileView {
            id: reader
            property string filePath: ""
            path: filePath
            printErrors: false
            onLoaded: {
                root.addFile(filePath, text());
                reader.destroy();
            }
            onLoadFailed: reader.destroy()
        }
    }

    // Honor XDG paths on other distributions, with the NixOS system profile fallback.
    readonly property var sessionDirectories: Array.from(new Set(
        (Quickshell.env("XDG_DATA_DIRS") || "/usr/local/share:/usr/share").split(":")
            .concat(["/run/current-system/sw/share"])
            .filter(path => path.startsWith("/"))
            .map(path => path + "/wayland-sessions")
    ))
    Instantiator {
        model: root.sessionDirectories
        delegate: FolderListModel {
            required property string modelData
            folder: "file://" + modelData
            nameFilters: ["*.desktop"]
            showDirs: false
            showDotAndDotDot: false
            onStatusChanged: {
                if (status !== FolderListModel.Ready) return;
                for (let i = 0; i < count; i++) {
                    let path = get(i, "filePath");
                    if (path.startsWith("file://")) path = path.slice(7);
                    if (!root.loadedPaths[path]) {
                        root.loadedPaths[path] = true;
                        desktopReader.createObject(root, {"filePath": path});
                    }
                }
            }
        }
    }
}

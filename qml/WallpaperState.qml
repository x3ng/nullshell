import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property bool synchronous: false
    property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quickshell/wallpaper.json"
    property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell/wallpaper.json"
    property var defaults: ({version: 1, outputs: {}})
    property var choices: ({version: 1, outputs: {}})
    property var pending: null
    property bool defaultsLoaded: false
    readonly property bool ready: defaultsLoaded && loaded
    property bool loaded: false
    property bool saving: false
    property string error: ""
    signal saved()

    function validEntry(entry) {
        return entry && typeof entry.path === "string" && entry.path.length > 0
            && ["cover", "contain", "stretch"].includes(entry.fit);
    }
    function parse(contents) {
        const data = JSON.parse(contents);
        if (!data || data.version !== 1 || !data.outputs || typeof data.outputs !== "object" || Array.isArray(data.outputs))
            throw new Error("Unsupported wallpaper configuration");
        if (data.default !== undefined && !validEntry(data.default)) throw new Error("Invalid default wallpaper");
        for (const entry of Object.values(data.outputs))
            if (!validEntry(entry)) throw new Error("Invalid display wallpaper");
        return data;
    }
    function entryFor(name) {
        let base;
        let saved;
        // A lock surface must not paint a placeholder before local settings arrive.
        if (synchronous) {
            base = {outputs: {}};
            saved = {outputs: {}};
            try { base = parse(configFile.text()); } catch (_) {}
            try { saved = parse(stateFile.text()); } catch (_) {}
        }
        else { base = defaults; saved = choices; }
        return saved.outputs[name] || saved.default || base.outputs[name] || base.default || {path: "", fit: "cover"};
    }
    function urlFor(path) {
        if (!path) return "";
        if (path.startsWith("~/")) path = Quickshell.env("HOME") + path.slice(1);
        if (path.startsWith("file://")) return path;
        if (!path.startsWith("/")) return "";
        return "file://" + path.split("/").map(part => encodeURIComponent(part)).join("/");
    }
    function apply(output, path, fit) {
        if (!loaded || saving || !validEntry({path: path, fit: fit}) || !urlFor(path)) return false;
        const next = JSON.parse(JSON.stringify(choices));
        if (output === "") {
            next.default = {path: path, fit: fit};
            next.outputs = {};
        } else next.outputs[output] = {path: path, fit: fit};
        pending = next;
        saving = true;
        error = "";
        stateFile.setText(JSON.stringify(next, null, 2) + "\n");
        return true;
    }
    FileView {
        id: configFile
        blockLoading: root.synchronous
        path: root.configPath
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoadFailed: root.defaultsLoaded = true
        onLoaded: {
            root.defaultsLoaded = true;
            try { root.defaults = root.parse(text()); }
            catch (e) { root.error = String(e); }
        }
    }
    FileView {
        id: stateFile
        blockLoading: root.synchronous
        path: root.statePath
        preload: true
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: if (!root.saving) reload()
        onLoaded: {
            if (root.saving) return;
            try { root.choices = root.parse(text()); root.error = ""; root.loaded = true; }
            catch (e) { root.error = String(e); root.loaded = false; }
        }
        onLoadFailed: error => {
            root.loaded = error === FileViewError.FileNotFound;
            if (!root.loaded) root.error = "Could not read wallpaper settings";
        }
        onSaved: {
            if (!root.pending) return;
            root.choices = root.pending;
            root.pending = null;
            root.saving = false;
            root.saved();
        }
        onSaveFailed: {
            root.pending = null;
            root.saving = false;
            root.error = "Could not save wallpaper settings";
        }
    }
}

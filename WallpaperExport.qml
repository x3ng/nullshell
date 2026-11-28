import QtQuick
import Quickshell
import Quickshell.Io
import "AppearanceRules.js" as Rules

Scope {
    id: root
    required property var wallpaper
    readonly property var selection: wallpaper.entryFor("")
    readonly property string source: {
        let value = selection.path;
        if (value.startsWith("~/")) value = Quickshell.env("HOME") + value.slice(1);
        if (value.startsWith("file:///")) {
            try { value = decodeURIComponent(value.slice(7)); } catch (_) { return "invalid:"; }
        }
        return value;
    }
    readonly property string explicitFile: Quickshell.env("NULLSHELL_WALLPAPER_EXPORT_FILE") || ""
    readonly property string baseDir: Quickshell.env("NULLSHELL_APPEARANCE_DIR") || "/var/lib/nullshell-appearance"
    readonly property string destination: explicitFile
        || Rules.slotFile(baseDir, Quickshell.env("USER") || "", "wallpaper.json")
    readonly property string contents: JSON.stringify({version: 1, source: source, fit: selection.fit})
    property int sourceGeneration: 0
    readonly property string requestKey: contents + ":" + sourceGeneration
    property string pendingKey: ""
    property string error: ""
    property string pending: ""
    property string saved: ""
    onRequestKeyChanged: Qt.callLater(publish)
    Connections {
        target: root.wallpaper
        function onReadyChanged() { Qt.callLater(root.publish); }
    }
    Component.onCompleted: Qt.callLater(publish)
    function publish() {
        if (!destination || !wallpaper.ready || writer.running || saved === requestKey) return;
        pending = contents;
        pendingKey = requestKey;
        writer.running = true;
    }
    FileView {
        path: root.destination && root.source.startsWith("/") ? root.source : ""
        preload: false
        watchChanges: path !== ""
        printErrors: false
        onFileChanged: root.sourceGeneration++
    }
    Process {
        id: writer
        command: root.explicitFile
            ? ["nullshell-helper", "wallpaper-export", root.destination]
            : ["nullshell-helper", "wallpaper-export", "--optional", root.destination]
        stdinEnabled: true
        onStarted: { write(root.pending); stdinEnabled = false; }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) console.warn("Wallpaper export:", text.trim())
        }
        onExited: (code, status) => {
            stdinEnabled = true;
            if (code === 0 && status === 0) { root.saved = root.pendingKey; root.error = ""; }
            else root.error = "Could not publish greeter wallpaper (PNG/JPEG/WebP, maximum 16 MiB)";
            if (root.requestKey !== root.pendingKey) Qt.callLater(root.publish);
        }
    }
}

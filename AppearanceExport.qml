import QtQuick
import Quickshell
import Quickshell.Io
import "AppearanceRules.js" as Rules

Scope {
    id: root
    required property var theme
    property bool ready: false
    // Export to the per-user 2750 slot when provisioned; explicit file paths remain supported.
    readonly property string explicitFile: Quickshell.env("NULLSHELL_APPEARANCE_EXPORT_FILE") || ""
    readonly property string baseDir: Quickshell.env("NULLSHELL_APPEARANCE_DIR") || "/var/lib/nullshell-appearance"
    property string exportPath: explicitFile
        || Rules.slotFile(baseDir, Quickshell.env("USER") || "", "theme.json")
    readonly property string contents: Rules.capture(theme)
    property string error: ""
    property string pending: ""
    property string saved: ""

    onContentsChanged: Qt.callLater(publish)
    onReadyChanged: Qt.callLater(publish)
    Component.onCompleted: Qt.callLater(publish)

    function publish() {
        if (!exportPath || !ready || writer.running || contents === saved) return;
        try { Rules.parse(contents); }
        catch (e) { error = String(e); return; }
        pending = contents;
        writer.command = explicitFile
            ? ["nullshell-helper", "appearance-export", exportPath]
            : ["nullshell-helper", "appearance-export", "--optional", exportPath];
        writer.running = true;
    }

    Process {
        id: writer
        stdinEnabled: true
        onStarted: { write(root.pending); stdinEnabled = false; }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) console.warn("Appearance export:", text.trim())
        }
        onExited: (code, status) => {
            stdinEnabled = true;
            if (code === 0 && status === 0) {
                root.saved = root.pending;
                root.error = "";
            } else root.error = "Could not publish appearance snapshot";
            // Coalesce changes without periodic polling or retry loops.
            if (root.contents !== root.pending) Qt.callLater(root.publish);
        }
    }
}

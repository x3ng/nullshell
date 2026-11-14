import QtQuick
import Quickshell
import Quickshell.Io
import "AppearanceRules.js" as Rules

Scope {
    id: root
    required property var theme
    property bool ready: false
    // Installation supplies these together. Permissions, not USER, enforce access.
    property string exportPath: Quickshell.env("NULLSHELL_APPEARANCE_SOURCE_USER") === Quickshell.env("USER")
        ? Quickshell.env("NULLSHELL_APPEARANCE_EXPORT_FILE") : ""
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
        writer.command = ["nullshell-helper", "appearance-export", exportPath];
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

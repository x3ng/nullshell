import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: adapter
    property var rows: []
    property string status: ""
    function refresh() {
        if (probe.running) return;
        rows = [];
        status = "Could not start hyprctl";
        probe.running = true;
    }
    Process {
        id: probe
        command: ["hyprctl", "-j", "binds"]
        stdout: StdioCollector { id: result }
        onStarted: adapter.status = "Reading shortcuts…"
        onExited: (code, exitStatus) => {
            try {
                if (code || exitStatus) throw new Error();
                // XKB modifier indices, in Hyprland modmask bit order.
                const names = ["Shift", "Caps", "Ctrl", "Alt", "Mod2", "Mod3", "Super", "Mod5"];
                adapter.rows = JSON.parse(result.text).map(bind => {
                    const chord = names.filter((_, bit) => bind.modmask & (1 << bit));
                    const key = bind.catch_all ? "Any key" : bind.key || (bind.keycode > 0 ? "code:" + bind.keycode : "Unknown key");
                    chord.push(key);
                    const raw = bind.dispatcher || "";
                    const dispatcher = raw.startsWith("function:") || raw === "__lua" ? "Lua callback" : raw;
                    return {chord: chord.join(" + "), description: [bind.submap, bind.description || dispatcher].filter(Boolean).join(" · "),
                        dispatcher: dispatcher};
                });
                adapter.status = adapter.rows.length ? "" : "No bindings reported";
            } catch (_) { adapter.status = "Could not read Hyprland bindings"; }
        }
    }
    Timer { interval: 3000; running: probe.running; onTriggered: probe.kill() }
}

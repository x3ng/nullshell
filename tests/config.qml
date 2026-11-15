import QtQuick
import Quickshell
import Quickshell.Io
import "ConfigRules.js" as Rules

ShellRoot {
    ShellConfig { id: config }
    IpcHandler {
        target: "config"
        function status(): string {
            return JSON.stringify({ready: config.ready, error: config.error, values: config.values});
        }
    }
    Component.onCompleted: {
        const invalid = ["null", "[]", "{}", '{"version":2}',
            '{"version":1,"appearance":{"mode":"solar"}}',
            '{"version":1,"appearance":{"mode":"unknown"}}',
            '{"version":1,"appearance":{"latitude":91}}',
            '{"version":1,"appearance":{"longitude":"0"}}',
            '{"version":1,"appearance":{"extra":true}}',
            '{"version":1,"typo":true}', '{"version":1,"terminal":"kitty"}',
            '{"version":1,"terminal":[""]}', '{"version":1,"terminal":[1]}',
            '{"version":1,"idle":{"dimSeconds":0}}',
            '{"version":1,"idle":{"lockSeconds":150}}',
            '{"version":1,"idle":{"dimSeconds":1.5}}',
            '{"version":1,"idle":{"displayOffSeconds":86401}}'];
        for (const value of invalid) {
            let rejected = false;
            try { Rules.parse(value); } catch (_) { rejected = true; }
            if (!rejected) throw new Error("Accepted invalid fixture: " + value);
        }
        if (Rules.parse('{"version":1,"terminal":[]}').terminal.length !== 0)
            throw new Error("Empty terminal must disable terminal launches");
        console.log("CONFIG_RULES_PASSED");
    }
}

import QtQuick
import Quickshell
import Quickshell.Io
import "ConfigRules.js" as Rules
import "adapters/SolarMath.js" as SolarMath

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
            '{"version":1,"appearance":{"mode":"unknown"}}',
            '{"version":1,"appearance":{"location":"unknown"}}',
            '{"version":1,"displays":{"mode":"unknown"}}',
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
        const auto = Rules.parse('{"version":1,"appearance":{"mode":"solar"}}').appearance;
        if (auto.mode !== "solar" || auto.location !== "timezone")
            throw new Error("Automatic appearance must default to offline time zone");
        const legacy = Rules.parse('{"version":1,"appearance":{"mode":"solar","location":"geoclue"}}').appearance;
        if (legacy.location !== "timezone")
            throw new Error("Legacy GeoClue settings must fall back to offline time zone");
        if (Rules.parse('{"version":1}').displays.mode !== "off"
            || Rules.parse('{"version":1,"displays":{"mode":"auto"}}').displays.mode !== "manual")
            throw new Error("Display profile handling must be opt-in");
        // Verify in-process NOAA solar calculation (equinox, date line, polar seasons, bounds).
        const t = 1710892800.0;
        const dawn = SolarMath.calculate(0.0, 0.0, t);
        if (!dawn || !dawn.dark || Math.abs(dawn.next_transition - t - 21840.0) >= 300.0)
            throw new Error("Unexpected equatorial sunrise transition");
        if (SolarMath.calculate(0.0, 0.0, t + 43200.0).dark
            || SolarMath.calculate(0.0, 180.0, t).dark !== SolarMath.calculate(0.0, -180.0, t).dark)
            throw new Error("Solar date-line or midday mismatch");
        if (SolarMath.calculate(90.0, 0.0, 1718928000.0).next_transition !== null
            || !SolarMath.calculate(-90.0, 0.0, 1718928000.0).dark
            || SolarMath.calculate(NaN, 0.0, t) !== null
            || SolarMath.calculate(0.0, 181.0, t) !== null)
            throw new Error("Solar polar or validation check failed");
        console.log("CONFIG_RULES_PASSED");
    }
}

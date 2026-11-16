// Pure configuration contract; no filesystem, process or UI dependencies.
function defaults() {
    return {version: 1, terminal: ["kitty", "--"],
        search: {aliases: {}},
        notifications: {persistHistory: true, historyDays: 7, recordTransient: false, excludedApplications: []},
        appearance: {mode: "manual", location: "fixed", latitude: null, longitude: null},
        idle: {dimSeconds: 150, lockSeconds: 300, displayOffSeconds: 600}};
}

function object(value, name, keys) {
    if (!value || typeof value !== "object" || Array.isArray(value))
        throw new Error(name + " must be an object");
    for (const key of Object.keys(value))
        if (!keys.includes(key)) throw new Error("Unknown " + name + " field: " + key);
}

function parse(text) {
    const input = JSON.parse(text);
    object(input, "config", ["version", "terminal", "idle", "appearance", "search", "notifications"]);
    if (input.version !== 1) throw new Error("Unsupported config version");
    const result = defaults();
    if (input.search !== undefined) {
        object(input.search, "search", ["aliases"]);
        const aliases = input.search.aliases;
        if (aliases !== undefined) {
            object(aliases, "search.aliases", Object.keys(aliases || {}));
            if (Object.keys(aliases).length > 128) throw new Error("Too many search aliases");
            for (const key of Object.keys(aliases)) {
                if (!/^(app|action):[^\s\u0000]{1,256}$/.test(key) || !Array.isArray(aliases[key])
                    || aliases[key].length > 16 || aliases[key].some(value => typeof value !== "string"
                        || !value.trim() || value.length > 128 || value.includes("\u0000")))
                    throw new Error("Invalid search alias: " + key);
            }
            result.search.aliases = aliases;
        }
    }
    if (input.notifications !== undefined) {
        object(input.notifications, "notifications", Object.keys(result.notifications));
        Object.assign(result.notifications, input.notifications);
        const n = result.notifications;
        if (typeof n.persistHistory !== "boolean" || typeof n.recordTransient !== "boolean"
            || !Number.isInteger(n.historyDays) || n.historyDays < 1 || n.historyDays > 365
            || !Array.isArray(n.excludedApplications) || n.excludedApplications.length > 128
            || n.excludedApplications.some(value => typeof value !== "string" || !value.trim()
                || value.length > 256 || value.includes("\u0000")))
            throw new Error("Invalid notification policy");
    }
    if (input.terminal !== undefined) {
        if (!Array.isArray(input.terminal) || input.terminal.length > 32
            || input.terminal.some(arg => typeof arg !== "string" || arg.length > 4096 || arg.includes("\u0000"))
            || (input.terminal.length && !input.terminal[0].trim()))
            throw new Error("terminal must be an argv array (or [] to disable terminal launches)");
        result.terminal = input.terminal.slice();
    }
    if (input.idle !== undefined) {
        object(input.idle, "idle", Object.keys(result.idle));
        for (const key of Object.keys(input.idle)) {
            const value = input.idle[key];
            if (!Number.isInteger(value) || value < 1 || value > 86400)
                throw new Error("idle." + key + " must be an integer from 1 to 86400");
            result.idle[key] = value;
        }
    }
    if (!(result.idle.dimSeconds < result.idle.lockSeconds
        && result.idle.lockSeconds < result.idle.displayOffSeconds))
        throw new Error("Idle deadlines must satisfy dim < lock < display off");
    if (input.appearance !== undefined) {
        object(input.appearance, "appearance", Object.keys(result.appearance));
        Object.assign(result.appearance, input.appearance);
        const a = result.appearance;
        if (!["manual", "solar"].includes(a.mode) || !["fixed", "geoclue"].includes(a.location))
            throw new Error("Invalid appearance mode or location source");
        for (const key of ["latitude", "longitude"]) {
            const limit = key === "latitude" ? 90 : 180;
            if (a[key] !== null && (typeof a[key] !== "number" || !Number.isFinite(a[key]) || Math.abs(a[key]) > limit))
                throw new Error("Invalid appearance coordinate");
        }
        if (a.mode === "solar" && a.location === "fixed" && (a.latitude === null || a.longitude === null))
            throw new Error("Fixed solar appearance requires latitude and longitude");
    }
    return result;
}

// Pure configuration contract; no filesystem, process or UI dependencies.
function defaults() {
    return {version: 1, terminal: ["kitty", "--"],
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
    object(input, "config", ["version", "terminal", "idle"]);
    if (input.version !== 1) throw new Error("Unsupported config version");
    const result = defaults();
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
    return result;
}

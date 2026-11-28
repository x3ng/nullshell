.pragma library

// Versioned data only: never import QML, paths or executable configuration.
var colorNames = ["backdrop", "panelSurface", "backgroundSurface", "surfaceRaised",
    "surfaceHover", "surfaceSelected", "materialEdge", "materialShadow", "wallpaperScrim",
    "inputSurface", "outline", "separator", "textPrimary", "textSecondary", "textMuted",
    "accent", "accentInk", "danger", "accentWarm"];

function parse(text) {
    if (text.length > 16384) throw new Error("Appearance snapshot is too large");
    var value = JSON.parse(text);
    if (!value || Array.isArray(value) || value.version !== 1
            || (value.mode !== "dark" && value.mode !== "light")
            || !value.colors || Array.isArray(value.colors)
            || Object.keys(value).sort().join(",") !== "colors,mode,version"
            || Object.keys(value.colors).sort().join(",") !== colorNames.slice().sort().join(","))
        throw new Error("Invalid appearance snapshot schema");
    colorNames.forEach(function(key) {
        if (typeof value.colors[key] !== "string"
                || !/^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(value.colors[key]))
            throw new Error("Invalid appearance colour: " + key);
    });
    return value;
}

function capture(theme) {
    var colors = {};
    colorNames.forEach(function(key) { colors[key] = String(theme[key]); });
    return JSON.stringify({version: 1, mode: theme.darkMode ? "dark" : "light", colors: colors}) + "\n";
}

function validSlotUser(name) {
    return typeof name === "string"
        && name.length >= 1
        && name.length <= 32
        && name !== "."
        && name !== ".."
        && name !== "greeter"
        && name !== "nobody"
        && /^[a-zA-Z0-9_][a-zA-Z0-9._-]*$/.test(name);
}

function slotFile(baseDir, userName, fileName) {
    if (!baseDir || baseDir === "off" || !validSlotUser(userName) || !fileName) return "";
    var trimmed = String(baseDir).replace(/\/+$/, "");
    if (!trimmed.startsWith("/")) return "";
    return trimmed + "/users/" + userName + "/" + fileName;
}

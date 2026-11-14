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

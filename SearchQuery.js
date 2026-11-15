.pragma library

// Command subscopes are visible query syntax, never hidden filter state.
function commandFilter(query) {
    const value = query.trim();
    return value.startsWith(">?") ? "panel" : value.startsWith(">!") ? "operation" : "all";
}
function commandText(query) {
    const value = query.trim();
    return value.slice(commandFilter(value) === "all" ? 1 : 2).trim();
}
function withCommandFilter(query, filter) {
    const prefix = filter === "panel" ? ">?" : filter === "operation" ? ">!" : ">";
    return prefix + " " + commandText(query);
}

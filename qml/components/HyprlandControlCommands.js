// Window addresses are validated; workspace addresses are quoted Lua data.
// Resolve existing targets again at execution time, including named/special workspaces.
function address(value) {
    if (typeof value !== "string") return "";
    const raw = value.toLowerCase().replace(/^0x/, "");
    return /^[0-9a-f]{1,16}$/.test(raw) && !/^0+$/.test(raw) ? "0x" + raw : "";
}
function compareWorkspaceAddresses(a, b) {
    const aNumeric = /^[1-9][0-9]*$/.test(a);
    const bNumeric = /^[1-9][0-9]*$/.test(b);
    if (aNumeric && bNumeric) return Number(a) - Number(b);
    return Number(bNumeric) - Number(aNumeric) || a.localeCompare(b);
}
function compareWorkspaces(a, b) {
    return Number(a.special) - Number(b.special) || compareWorkspaceAddresses(a.address, b.address);
}
function luaString(value) {
    // Fixed-width decimal escapes also handle newlines/NUL without consuming following digits.
    return '"' + value.replace(/[\\"\x00-\x1f\x7f]/g,
        c => "\\" + String(c.charCodeAt(0)).padStart(3, "0")) + '"';
}
function workspaceGuard(row, allowEmpty) {
    if (!row || typeof row.address !== "string" || !row.address) return null;
    if (!row.exists) {
        if (!allowEmpty || !/^(?:[1-9]|10)$/.test(row.address)) return null;
        return "local target = " + row.address + "; ";
    }
    // Equality avoids interpreting a display name or address as a relative selector.
    return "local target; for _, ws in ipairs(hl.get_workspaces()) do if ws.addressable_name == "
        + luaString(row.address) + " then target = ws; break end end; "
        + "if not target then return 'ERROR: Workspace no longer exists' end; ";
}
function result(dispatcher) {
    return "local result = hl.dispatch(" + dispatcher + "); "
        + "if not result or not result.ok then return 'ERROR: ' .. tostring(result and result.error or 'Operation failed') end; return 'OK'";
}
function windowAction(action, windowRow, workspaceRow) {
    const target = address(windowRow?.address);
    if (!target) return {error: "Window no longer exists"};
    let prefix = "local win = hl.get_window('address:" + target
        + "'); if not win or not win.mapped then return 'ERROR: Window no longer exists' end; ";
    let dispatch;
    if (action === "focus") dispatch = "hl.dsp.focus({window = win})";
    else if (action === "float") dispatch = "hl.dsp.window.float({window = win, action = 'toggle'})";
    else if (action === "fullscreen") dispatch = "hl.dsp.window.fullscreen({window = win, mode = 'fullscreen', action = 'toggle'})";
    else if (action === "close") dispatch = "hl.dsp.window.close({window = win})";
    else if (action === "move") {
        const guard = workspaceGuard(workspaceRow, true);
        if (!guard) return {error: "Workspace no longer exists"};
        prefix += guard;
        dispatch = "hl.dsp.window.move({window = win, workspace = target, follow = false})";
    } else return {error: "Unknown window operation"};
    return {code: prefix + result(dispatch)};
}
function workspaceAction(action, workspaceRow, layout) {
    const guard = workspaceGuard(workspaceRow, action === "focus");
    if (!guard) return {error: "Enter this workspace before changing its layout"};
    if (action === "focus") return {code: guard + result("hl.dsp.focus({workspace = target})")};
    if (action !== "layout" || !["dwindle", "master", "scrolling", "monocle"].includes(layout))
        return {error: "Unknown workspace layout"};
    return {code: guard
        + "local ok, message = require('workspaces').set_layout(target, '" + layout + "'); "
        + "if not ok then return 'ERROR: ' .. tostring(message) end; return 'OK'"};
}

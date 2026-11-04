pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: searchModel
    required property string query
    property var actions: null
    // Terminal executable and its argument separator; argv stays an array.
    required property list<string> terminalCommand
    // Optional scopes keep the default query global without requiring a mode switch.
    // A bare scope shows its complete catalog; an empty global query shows home.
    readonly property string scope: query.trim().startsWith(">") ? "ACTION"
        : query.trim().startsWith("@") ? "WINDOW"
        : (query.trim().startsWith("/") || /^apps:/i.test(query.trim())) ? "APP" : "ALL"
    readonly property string searchText: {
        const value = query.trim();
        return (scope === "ACTION" || scope === "WINDOW" ? value.slice(1)
            : scope === "APP" ? value.slice(value.startsWith("/") ? 1 : 5) : value).trim();
    }
    readonly property string scopeLabel: scope === "ACTION" ? "Commands"
        : scope === "WINDOW" ? "Open windows" : scope === "APP" ? "Applications" : "Results"

    function matchScore(text, needle) {
        const value = String(text || "").toLocaleLowerCase();
        if (!needle) return 0;
        if (value === needle) return 0;
        if (value.startsWith(needle)) return 10;
        const terms = needle.split(/\s+/).filter(Boolean);
        let total = 0;
        for (const term of terms) {
            const index = value.indexOf(term);
            if (index < 0) return 1000;
            total += index === 0 ? 10 : /[\s\-_./]/.test(value[index - 1]) ? 20 : 30;
        }
        return total / terms.length;
    }

    readonly property var results: {
        if (!query.trim()) return [];
        const q = searchText.toLocaleLowerCase();
        const terms = q ? q.split(/\s+/).filter(Boolean) : [];
        const matches = text => terms.every(term => String(text).toLocaleLowerCase().includes(term));
        const ranked = (name, metadata) => {
            const title = matchScore(name, q);
            // All query terms must match the title for it to receive title priority.
            // Keywords remain searchable without outranking a direct name match.
            return title < 1000 ? title : 100 + matchScore(metadata, q);
        };
        const windows = scope === "ALL" || scope === "WINDOW"
            ? ToplevelManager.toplevels.values.map((window, order) => {
                const entry = desktopEntryFor(window);
                const nativeWindow = Hyprland.toplevels.values.find(w => w.wayland === window);
                const workspace = nativeWindow?.workspace;
                const location = workspace?.name || workspace?.address || "";
                const appName = entry?.name || window.appId;
                return {key: window, kind: "WINDOW", title: window.title || window.appId,
                    detail: appName + (location ? " · Workspace " + String(location).replace(/^special:/, "") : ""), appId: window.appId, entry: entry, target: window, order: order};
            }).filter(row => matches(row.title + " " + row.detail + " " + row.appId))
                .map(row => { row.score = ranked(row.title, row.title + " " + row.detail + " " + row.appId); return row; }) : [];
        const apps = scope === "ALL" || scope === "APP"
            ? DesktopEntries.applications.values.filter(app => !app.noDisplay
                && matches([app.name, app.genericName, app.comment, app.id].join(" ")))
                .map(app => ({key: "app:" + app.id, kind: "APP", title: app.name,
                    detail: app.genericName && app.genericName !== app.name ? app.genericName : app.comment || "Open application",
                    entry: app, target: app,
                    score: ranked(app.name, [app.name, app.genericName, app.comment, app.id].join(" "))}))
                .sort((a, b) => a.title.localeCompare(b.title))
                .map((app, order) => { app.order = order; return app; }) : [];
        const commands = scope === "ALL" || scope === "ACTION"
            ? (actions?.entries ?? []).map((action, order) => {
                const keywords = Array.isArray(action.keywords) ? action.keywords.join(" ") : action.keywords || "";
                return {key: "action:" + action.id, kind: "ACTION", title: action.title,
                    detail: action.description || "Desktop command", keywords: keywords,
                    icon: action.icon || "app", enabled: action.enabled !== false,
                    target: action, order: order};
            }).filter(row => matches(row.title + " " + row.keywords))
                .map(row => { row.score = ranked(row.title, row.title + " " + row.keywords); return row; }) : [];
        const kindOrder = {WINDOW: 0, APP: 1, ACTION: 2};
        return windows.concat(apps, commands).sort((a, b) => a.score - b.score
            || kindOrder[a.kind] - kindOrder[b.kind] || a.order - b.order);
    }

    function normalizedDesktopId(value) {
        return (value ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    function desktopEntryFor(toplevel) {
        const appId = toplevel?.appId ?? "";
        if (!appId) return null;
        const exact = DesktopEntries.heuristicLookup(appId);
        if (exact) return exact;
        const wanted = normalizedDesktopId(appId);
        if (!wanted) return null;
        var entries = DesktopEntries.applications?.values ?? [];
        for (var j = 0; j < entries.length; j++) {
            var entry = entries[j];
            if (searchModel.normalizedDesktopId(entry.id) === wanted
                || searchModel.normalizedDesktopId(entry.startupClass) === wanted)
                return entry;
        }
        return null;
    }

    function desktopIconSource(entry) {
        var icon = entry?.icon ?? "";
        if (!icon) return "";
        return icon.startsWith("/") ? "file://" + icon : "image://icon/" + icon;
    }

    function launchApplication(entry, forceTerminal = false) {
        if (!entry.command.length) return false;
        const inTerminal = forceTerminal || entry.runInTerminal;
        if (inTerminal && !terminalCommand.length) return false;
        const argv = inTerminal ? [...terminalCommand, ...entry.command] : [...entry.command];
        // Detached processes still inherit this service's cgroup. Move the whole
        // application (including a terminal wrapper) into its own user scope.
        // Disable systemd's $VAR expansion so desktop-entry arguments stay literal.
        Quickshell.execDetached({
            command: ["systemd-run", "--user", "--scope", "--collect", "--quiet",
                "--slice=app.slice", "--expand-environment=no", "--", ...argv],
            workingDirectory: entry.workingDirectory
        });
        return true;
    }

    function activate(index, forceTerminal = false) {
        return activateResult(results[index], forceTerminal);
    }

    // Returns {accepted, closePanel}. Accepted means the request was dispatched,
    // not that an asynchronous app launch or compositor focus has completed.
    // Capture the row before clearing a query can reorder the model.
    function activateResult(result, forceTerminal = false) {
        if (!result || result.enabled === false) return {accepted: false, closePanel: false};
        if (result.kind === "ACTION") {
            return {accepted: actions?.execute(result.target.id) === true, closePanel: false};
        }
        if (result.kind === "WINDOW") {
            if (!ToplevelManager.toplevels.values.includes(result.target))
                return {accepted: false, closePanel: false};
            result.target.activate();
            return {accepted: true, closePanel: true};
        }
        if (result.kind === "APP") {
            const accepted = launchApplication(result.target, forceTerminal);
            return {accepted: accepted, closePanel: accepted};
        }
        return {accepted: false, closePanel: false};
    }
}

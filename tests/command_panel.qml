import QtQuick
import Quickshell
import Quickshell.Io
import "SearchMatch.js" as Match
import "ConfigRules.js" as Rules
import "components/NotificationUtils.js" as NotificationUtils
import "preview"
import "adapters"

ShellRoot {
    id: root
    property var failures: []
    HyprlandBindings { id: bindingsAdapter }
    ApplicationLauncher {
        id: launcher
        onFeedback: (key, summary, body, critical) => root.failures = [...root.failures, {summary: summary, body: body}]
    }
    Notifications { id: notifs; settingsReady: false }
    PanelFixture {
        id: fixture
        property var powerProfiles: ["balanced"]
        property bool powerAvailable: true
    }
    ShellActions {
        id: shellActions
        services: fixture
        appearance: fixture
        keyboard: fixture
        notifs: notifs
    }
    DesktopSearch {
        id: search
        query: ""
        terminalCommand: []
        aliases: ({"app:org.nullshell.Synthetic.desktop": ["测试应用"]})
        actions: shellActions
    }
    IpcHandler {
        target: "test"
        function cacheDirectory(): string { return Quickshell.cacheDir; }
        function status(): string {
            return JSON.stringify({ready: notifs.historyLoaded && notifs.quietReady,
                quiet: notifs.doNotDisturb, until: notifs.quietUntil,
                history: notifs.history, current: notifs.current, popups: notifs.popups.map(w => w.summary),
                live: notifs.liveNotifications.length, jobs: launcher.jobs.length, failures: root.failures,
                error: notifs.persistenceError || notifs.quietError});
        }
        function configure(value: string): void { notifs.settings = Rules.parse(value).notifications; notifs.settingsReady = true; }
        function command(value: string): bool { return shellActions.execute(value); }
        function refreshBindings(): void { bindingsAdapter.refresh(); }
        function bindings(): string { return JSON.stringify(bindingsAdapter.rows); }
        function searchFor(value: string): string {
            search.query = value;
            return JSON.stringify(search.results.map(row => ({title: row.title, kind: row.kind, key: row.key})));
        }
        function pause(): bool { return notifs.pause(60); }
        function resume(): bool { return notifs.resume(); }
        function checkLocalAction(): bool {
            let opened = false;
            notifs.notifyLocal("capture-test", {summary: "Synthetic screenshot", actions: [
                {identifier: "open", text: "Open image", invoke: () => { opened = true; }}
            ]});
            const entry = notifs.current.find(row => row.recordKey === "local:capture-test");
            const action = notifs.entryActions(entry)[0];
            const invoked = action && notifs.invokeEntryAction(entry, action);
            notifs.closeLocal("capture-test");
            return !!invoked && opened && !entry.actions;
        }
        function local(key: string, critical: bool): void { notifs.notifyLocal(key, {summary: key, critical: critical}); }
        function clear(): void { notifs.clearHistory(); }
        function launch(name: string, terminal: bool): bool {
            return launcher.launch({name: name, command: [name, "$literal", "a b", "`literal`"],
                runInTerminal: terminal, workingDirectory: "/tmp"}, ["test-terminal", "--"], false);
        }
        function quit(): void { Qt.quit(); }
    }
    Component.onCompleted: {
        function check(ok, message) { if (!ok) throw new Error(message); }
        check(Match.score("Firefox", "", "firefox") === 0, "Exact name");
        check(Match.score("Firefox", "", "ff") < 1000, "Abbreviation");
        check(Match.score("Visual Studio Code", "", "vsc") < 1000, "Initials");
        check(Match.score("Wi-Fi settings", "无线 网络", "无线") < 1000, "Chinese keyword");
        check(Match.score("Firefox", "火狐 浏览器", "火狐") < 1000, "Alias");
        check(Match.score("Firefox", "", "ff") > Match.score("Other", "ff", "ff"), "Literal metadata priority");
        check(Match.score("abcdef", "", "zz") === 1000, "Unrelated result");
        check(Match.score("Browser", "some long comment text", "slct") === 1000, "No fuzzy comments");
        check(Match.score("Firefox", "", "非") === 1000, "No fuzzy CJK");
        const valid = Rules.parse('{"version":1,"search":{"aliases":{"app:firefox.desktop":["火狐","ff"]}},"notifications":{"persistHistory":false,"historyDays":3}}');
        check(valid.search.aliases["app:firefox.desktop"][0] === "火狐", "Alias config");
        for (const value of [
            {search: {aliases: {bad: ["x"]}}}, {search: {aliases: {"app:x": "x"}}},
            {search: {aliases: {"action:x": [""]}}}, {search: {aliases: null}},
            {notifications: {historyDays: 0}}, {notifications: {persistHistory: "false"}},
            {notifications: {excludedApplications: [1]}}, {notifications: {extra: true}}
        ]) {
            let rejected = false;
            try { Rules.parse(JSON.stringify(Object.assign({version: 1}, value))); } catch (_) { rejected = true; }
            check(rejected, "Invalid policy accepted");
        }
        check(NotificationUtils.imageSource("image://icon//tmp/.tmp9HiLUa/.tmpxZhuTB.png")
            === "file:///tmp/.tmp9HiLUa/.tmpxZhuTB.png", "Unwrap Quickshell icon-wrapped file path");
        check(NotificationUtils.attachmentSource("image://icon//tmp/shot.png") === "file:///tmp/shot.png",
            "Attachment file URL");
        check(NotificationUtils.attachmentSource("image://icon/firefox") === "",
            "Symbolic theme icon must not render as body attachment");
        check(NotificationUtils.imageSource("missing-icon", () => "") === "",
            "Missing theme icon returns empty instead of missing-texture checkerboard");
        check(NotificationUtils.savedImage("image://qsimage/12") === "",
            "Live qsimage is not persisted to disk");
        console.log("COMMAND_RULES_OK");
    }
}

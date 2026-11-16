pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Short-lived dispatch clients; applications belong to independent user units.
// Type=exec reports failed execs before systemd-run returns, without --wait.
Scope {
    id: root
    signal feedback(string key, string summary, string body, bool critical)
    property var jobs: []

    function launch(entry, terminal, forceTerminal) {
        const command = entry?.command;
        if (!command?.length || ((forceTerminal || entry.runInTerminal) && !terminal.length)) {
            feedback("app-launch", "Could not launch application", "The application command or configured terminal is missing.", false);
            return false;
        }
        if (jobs.length >= 8) {
            feedback("app-launch", "Could not launch application", "Too many launch requests are pending. Please try again shortly.", false);
            return false;
        }
        const argv = forceTerminal || entry.runInTerminal ? [...terminal, ...command] : [...command];
        const directory = entry.workingDirectory ? ["--working-directory=" + entry.workingDirectory] : ["--same-dir"];
        // Import session context by variable NAME, never by putting values
        // (which may be private) in argv. User-manager activation environments
        // need not contain the compositor's current display or input settings.
        const environment = ["PATH", "WAYLAND_DISPLAY", "DISPLAY", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE",
            "XDG_SESSION_DESKTOP", "HYPRLAND_INSTANCE_SIGNATURE", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS",
            "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_DATA_DIRS", "XDG_STATE_HOME", "XDG_CACHE_HOME",
            "QT_QPA_PLATFORMTHEME", "QT_IM_MODULE", "GTK_IM_MODULE", "XMODIFIERS", "XAUTHORITY",
            "SSH_AUTH_SOCK", "LANG", "LANGUAGE", "LC_ALL", "LC_CTYPE"]
            .filter(name => !!Quickshell.env(name)).map(name => "--setenv=" + name);
        const job = jobComponent.createObject(root, {label: entry.name || "Application",
            argv: ["systemd-run", "--user", "--collect", "--quiet", "--service-type=exec",
                "--slice=app.slice", "--expand-environment=no", "--property=ExitType=cgroup",
                "--property=TimeoutStartSec=10s", ...directory, ...environment, "--", ...argv]});
        jobs = [...jobs, job];
        job.start();
        return true;
    }
    Component {
        id: jobComponent
        QtObject {
            id: job
            required property string label
            required property var argv
            property string failure: ""
            property bool started: false
            property bool finished: false
            function start() { process.running = true; deadline.start(); }
            function finish(message) {
                if (finished) return;
                finished = true;
                deadline.stop();
                if (message) root.feedback("app-launch", "Could not launch " + label, message, false);
                root.jobs = root.jobs.filter(item => item !== job);
                Qt.callLater(() => job.destroy());
            }
            readonly property Timer deadline: Timer {
                interval: 15000
                onTriggered: {
                    process.running = false;
                    job.finish("The launch request timed out; the application may still start. Check the user service journal.");
                }
            }
            readonly property Process process: Process {
                command: job.argv
                onStarted: job.started = true
                onRunningChanged: if (!running && !job.started)
                    job.finish("Could not start systemd-run. Check that it is installed and executable.")
                stderr: SplitParser { onRead: data => { job.failure = (job.failure + data + "\n").slice(-2048); } }
                onExited: (code, status) => job.finish(code === 0 && status === 0 ? ""
                    : job.failure.trim() || "The user service manager rejected the launch request.")
            }
        }
    }
}

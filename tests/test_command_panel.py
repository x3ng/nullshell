"""Real QML search rules, dispatch failures and notification policy on private buses.

Uses synthetic executables/accounts/data only; never contacts a host service.
"""
import asyncio
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

from dbus_next import Message, Variant
from dbus_next.aio import MessageBus


with tempfile.TemporaryDirectory(prefix="ns-command-", dir="/tmp") as directory:
    base = Path(directory)
    source = Path(__file__).resolve().parent
    for name in ["ApplicationLauncher.qml", "DesktopSearch.qml", "ShellActions.qml", "SessionActions.qml", "SearchQuery.js", "Notifications.qml", "NotificationQuiet.qml", "SearchMatch.js", "ConfigRules.js"]:
        shutil.copy2(source.parent / name, base / name)
    (base / "components").mkdir()
    shutil.copy2(source.parent / "components/NotificationUtils.js", base / "components/NotificationUtils.js")
    (base / "preview").mkdir()
    shutil.copy2(source.parent / "preview/PanelFixture.qml", base / "preview/PanelFixture.qml")
    shutil.copy2(source / "command_panel.qml", base / "shell.qml")
    binaries = base / "bin"
    binaries.mkdir()
    executable = binaries / "systemd-run"
    executable.write_text("#!" + sys.executable + "\n" + '''import json,os,pathlib,sys,time
args=sys.argv[1:]
with open(os.environ['TEST_CALLS'],'a') as out: out.write(json.dumps(args)+'\\n')
if 'denied' in args:
    print('Synthetic exec denial',file=sys.stderr)
    sys.exit(1)
if 'slow' in args: time.sleep(20)
''')
    executable.chmod(0o755)
    env = dict(os.environ, HOME=str(base), XDG_CONFIG_HOME=str(base / "config"),
               XDG_STATE_HOME=str(base / "state"), XDG_CACHE_HOME=str(base / "cache"),
               XDG_RUNTIME_DIR=str(base), QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
               PATH=str(binaries), TEST_CALLS=str(base / "calls"),
               DBUS_SYSTEM_BUS_ADDRESS="unix:path=" + str(base / "no-system"))
    for key in ["WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"]:
        env.pop(key, None)
    quickshell = shutil.which("quickshell")
    # Supply the bus configuration explicitly: /etc/dbus-1 need not exist in a
    # Nix build sandbox, and activation of unrelated session services is unwanted.
    bus_config = base / "session.conf"
    bus_config.write_text('<busconfig><type>session</type><listen>unix:tmpdir=' + str(base)
        + '</listen><auth>EXTERNAL</auth><policy context="default">'
        + '<allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/>'
        + '</policy></busconfig>')
    bus = subprocess.Popen([shutil.which("dbus-daemon"), "--config-file=" + str(bus_config), "--nofork", "--print-address=1"],
                           env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    env["DBUS_SESSION_BUS_ADDRESS"] = bus.stdout.readline().strip()
    assert env["DBUS_SESSION_BUS_ADDRESS"], "Private notification bus did not start"
    entry = str(base / "shell.qml")
    history_file = base / "state/nullshell/notifications.json"
    history_file.parent.mkdir(parents=True)
    applications = base / "data/applications"
    applications.mkdir(parents=True)
    (applications / "org.nullshell.Synthetic.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=Visual Studio Code Synthetic\nExec=never-execute-synthetic\n")
    env["XDG_DATA_HOME"] = str(applications.parent)
    env["XDG_DATA_DIRS"] = str(base / "no-system-applications")
    stale = {"recordKey": "stale", "summary": "old", "appName": "Test", "time": 1}
    history_file.write_text(json.dumps({"version": 1, "notifications": [stale], "current": [stale]}))
    log = base / "qml.log"
    process = None

    def call(*args):
        return subprocess.check_output([quickshell, "ipc", "--path", entry, "call", "test", *args],
                                       env=env, text=True, stderr=subprocess.DEVNULL, timeout=3).strip()

    def wait_for(predicate, timeout=8):
        end = time.monotonic() + timeout
        last = None
        while time.monotonic() < end:
            try:
                last = json.loads(call("status"))
                if predicate(last):
                    return last
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass
            if process.poll() is not None:
                break
            time.sleep(.05)
        raise AssertionError(f"State did not settle: {last}\n{log.read_text()}")

    def start(policy='{"version":1}', early=False):
        global process
        with log.open("a") as output:
            process = subprocess.Popen([quickshell, "--path", entry], env=env, stdout=output, stderr=output)
        wait_for(lambda s: True)
        # Real saved history must wait until configuration has been published.
        assert not json.loads(call("status"))["ready"]
        if early:
            asyncio.run(send("startup excluded"))
        call("configure", policy)
        return wait_for(lambda s: s["ready"])

    def stop():
        call("quit")
        process.wait(timeout=4)

    async def send(summary, transient=False, critical=False, replaces=0, application="Test"):
        connection = await MessageBus(bus_address=env["DBUS_SESSION_BUS_ADDRESS"]).connect()
        try:
            result = await connection.call(Message(destination="org.freedesktop.Notifications",
                path="/org/freedesktop/Notifications", interface="org.freedesktop.Notifications", member="Notify",
                signature="susssasa{sv}i", body=[application, replaces, "", summary, "synthetic body", [],
                    {"transient": Variant("b", transient), "urgency": Variant("y", 2 if critical else 1)}, 5000]))
            assert result.error_name is None, result.body
            return result.body[0]
        finally:
            connection.disconnect()

    try:
        initial = start()
        assert not initial["history"] and not initial["current"], initial
        assert not json.loads(call("searchFor", ""))
        wait_for(lambda s: bool(json.loads(call("searchFor", "/"))))
        for query in ["/ vscs", "/ 测试应用"]:
            result = json.loads(call("searchFor", query))
            assert len(result) == 1 and result[0]["kind"] == "APP", (query, result, call("searchFor", "/"))
        audio = json.loads(call("searchFor", ">? 音频"))
        assert [row["title"] for row in audio] == ["Audio devices"], (audio, log.read_text())
        assert not json.loads(call("searchFor", ">! 音频"))
        assert call("launch", "denied", "false") == "true"
        failed = wait_for(lambda s: len(s["failures"]) == 1 and s["jobs"] == 0)
        assert "Synthetic exec denial" in failed["failures"][0]["body"], failed
        call("launch", "success", "true")
        wait_for(lambda s: s["jobs"] == 0)
        calls = [json.loads(line) for line in (base / "calls").read_text().splitlines()]
        assert calls[0][-4:] == ["denied", "$literal", "a b", "`literal`"], calls
        assert calls[1][-6:] == ["test-terminal", "--", "success", "$literal", "a b", "`literal`"], calls
        assert "--service-type=exec" in calls[0] and "--property=ExitType=cgroup" in calls[0]
        assert "--working-directory=/tmp" in calls[0] and "--expand-environment=no" in calls[0]
        executable.rename(binaries / "disabled")
        call("launch", "missing", "false")
        missing = wait_for(lambda s: len(s["failures"]) == 2 and s["jobs"] == 0)
        assert "Could not start systemd-run" in missing["failures"][-1]["body"], missing
        (binaries / "disabled").rename(executable)
        call("launch", "slow", "false")
        timed_out = wait_for(lambda s: len(s["failures"]) == 3 and s["jobs"] == 0, timeout=18)
        assert "timed out" in timed_out["failures"][-1]["body"]
        assert call("command", "notifications-pause") == "true"
        assert call("command", "notifications-pause") == "false"
        wait_for(lambda s: s["quiet"])
        identifier = asyncio.run(send("muted"))
        muted = wait_for(lambda s: any(e["summary"] == "muted" for e in s["current"]))
        assert not muted["popups"], muted
        asyncio.run(send("updated while muted", replaces=identifier))
        updated = wait_for(lambda s: any(e["summary"] == "updated while muted" for e in s["current"]))
        assert not updated["popups"] and len(updated["current"]) == 1, updated
        asyncio.run(send("critical", critical=True))
        wait_for(lambda s: "critical" in s["popups"])
        asyncio.run(send("transient", transient=True))
        time.sleep(.15)
        state = json.loads(call("status"))
        assert not any(e["summary"] == "transient" for e in state["history"]), state
        assert state["live"] == 2, state
        stop()
        restored = start()
        assert restored["quiet"] and not restored["popups"], restored
        assert call("command", "notifications-resume") == "true"
        assert call("command", "notifications-resume") == "false"
        assert not wait_for(lambda s: not s["quiet"])["popups"]
        call("configure", '{"version":1,"notifications":{"excludedApplications":["Test"]}}')
        asyncio.run(send("excluded"))
        excluded = wait_for(lambda s: "excluded" in s["popups"])
        assert not excluded["history"] and not excluded["current"], excluded
        call("configure", '{"version":1,"notifications":{"persistHistory":false}}')
        call("local", "memory only", "false")
        wait_for(lambda s: any(e["summary"] == "memory only" for e in s["history"]))
        time.sleep(.4)
        disk = json.loads(history_file.read_text())
        assert not disk["notifications"] and not disk["current"], disk
        stop()
        assert not start()["history"]
        stop()
        # An elapsed period must not reactivate after process restart.
        quiet_file = base / "state/nullshell/notification-quiet.json"
        quiet_file.write_text(json.dumps({"version": 1, "until": time.time() * 1000 - 1000}))
        assert not start()["quiet"]
        stop()
        quiet_file.write_text(json.dumps({"version": 1, "until": time.time() * 1000 + 2000}))
        assert start()["quiet"]
        wait_for(lambda s: not s["quiet"], timeout=4)
        stop()
        early = start('{"version":1,"notifications":{"excludedApplications":["Test"]}}', early=True)
        assert not early["history"] and not early["current"], early
        wait_for(lambda s: "startup excluded" in s["popups"])
        stop()
        # Invalid state is reported and preserved, including when persistence
        # is disabled. A policy change cannot silently erase a corrupt file.
        quiet_file.write_text("invalid quiet state")
        history_file.write_text("invalid history state")
        invalid = start()
        assert invalid["error"] and not invalid["quiet"], invalid
        call("configure", '{"version":1,"notifications":{"persistHistory":false}}')
        call("local", "unsaved", "false")
        time.sleep(.3)
        assert history_file.read_text() == "invalid history state"
        assert quiet_file.read_text() == "invalid quiet state"
        stop()
        text = log.read_text()
        assert "COMMAND_RULES_OK" in text, text
        assert not any(word in text for word in ["ReferenceError", "TypeError", "SyntaxError", "Binding loop"]), text
        print("Command panel: matching, validation, launch failures/timeout and notification policy/restarts passed")
    finally:
        if process and process.poll() is None:
            process.terminate()
            process.wait(timeout=4)
        bus.terminate()
        bus.wait(timeout=4)

#!/usr/bin/env python3
"""Manual QML mode -> persistent state and greeter export."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
from test_wallpaper import png

ROOT = Path(__file__).resolve().parent.parent
HELPER = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="ns-theme-", dir="/tmp") as directory:
    base = Path(directory)
    source = base / "source"
    source.mkdir()
    # Keep this exported sample only when explicitly requested for visual checks.
    for name in ("AppearanceState.qml", "AppearanceSchedule.qml", "AppearancePreferences.qml", "ConfigRules.js", "Appearance.qml", "AppearanceExport.qml",
                 "AppearanceSnapshot.qml", "AppearanceRules.js", "Theme.qml", "SurfaceCapabilities.qml",
                 "WallpaperState.qml", "WallpaperExport.qml", "GreeterWallpaper.qml", "WallpaperImage.qml"):
        shutil.copy2(ROOT / name, source / name)
    for name in ("AppearanceExport.qml", "WallpaperExport.qml"):
        exporter = source / name
        exporter.chmod(0o600)
        exporter.write_text(exporter.read_text().replace('"nullshell-helper"', json.dumps(str(HELPER))))
    shutil.copytree(ROOT / "components", source / "components")
    shutil.copytree(ROOT / "adapters", source / "adapters")
    tools = base / "bin"
    tools.mkdir()
    (tools / "nullshell-helper").symlink_to(HELPER)
    runtime = base / "runtime"
    runtime.mkdir(mode=0o700)
    slot_root = base / "relocated shared directory"
    shared = slot_root / "users" / "fixture-user" / "theme.json"
    shared.parent.mkdir(parents=True)
    wallpaper_file = shared.parent / "wallpaper.json"
    image_file = base / "synthetic image.png"
    image_file.write_bytes(png(30, 60, 90))
    state = base / "relocated state"
    entry = source / "test.qml"
    entry.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "AppearanceRules.js" as Rules
ShellRoot {
    id: root
    property string activeUser: "fixture-user"
    AppearanceState { id: mode }
    Theme { id: theme; darkMode: mode.darkMode; previewBlur: 0 }
    AppearanceExport { id: publisher; theme: theme; ready: mode.appearanceKnown }
    AppearanceSnapshot {
        id: reader
        path: Rules.slotFile(Quickshell.env("NULLSHELL_APPEARANCE_DIR"), root.activeUser, "theme.json")
    }
    WallpaperState { id: wallpaper }
    WallpaperExport { id: wallpaperExport; wallpaper: wallpaper }
    GreeterWallpaper {
        id: background
        width: 100
        height: 80
        snapshotPath: Rules.slotFile(Quickshell.env("NULLSHELL_APPEARANCE_DIR"), root.activeUser, "wallpaper.json")
    }
    IpcHandler {
        target: "test"
        function setWallpaper(path: string, fit: string): bool { return wallpaper.apply("", path, fit); }
        function setMode(dark: bool): bool { return mode.setTheme(dark); }
        function setUser(name: string): void { root.activeUser = name; }
        function status(): string {
            return JSON.stringify({available: mode.appearanceAvailable, mode: mode.darkMode,
                snapshot: reader.snapshot, wallpaperReady: background.ready, wallpaperSnapshot: background.snapshot,
                wallpaperError: wallpaperExport.error || background.error,
                readError: reader.error, writeError: publisher.error});
        }
    }
}''')
    env = dict(os.environ, HOME=str(base), XDG_STATE_HOME=str(state),
               XDG_CONFIG_HOME=str(base / "config"), XDG_CACHE_HOME=str(base / "cache"),
               XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
               DBUS_SESSION_BUS_ADDRESS="unix:path=" + str(base / "no-session-bus"),
               DBUS_SYSTEM_BUS_ADDRESS="unix:path=" + str(base / "no-system-bus"),
               USER="fixture-user", NULLSHELL_APPEARANCE_DIR=str(slot_root),
               PATH=str(tools) + ":" + os.environ["PATH"])
    for key in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE",
                "NULLSHELL_APPEARANCE_EXPORT_FILE", "NULLSHELL_WALLPAPER_EXPORT_FILE",
                "NULLSHELL_APPEARANCE_FILE", "NULLSHELL_WALLPAPER_FILE"):
        env.pop(key, None)
    log = base / "qml.log"

    def ipc(method, *args):
        return subprocess.run(["quickshell", "ipc", "--path", str(entry), "call", "test", method, *args],
                              env=env, capture_output=True, text=True, timeout=3)

    def wait(predicate):
        until = time.monotonic() + 12
        last = None
        while time.monotonic() < until:
            result = ipc("status")
            if result.returncode == 0:
                last = json.loads(result.stdout)
                if predicate(last):
                    return last
            time.sleep(.1)
        raise AssertionError(f"State: {last}\n{log.read_text()}")

    def replace(text):
        temp = shared.with_suffix(".tmp")
        temp.write_text(text)
        temp.replace(shared)

    def broadcast(mode):
        # All mode changes are explicit user commands, with no scheduling peer.
        assert ipc("setMode", "true" if mode == "dark" else "false").returncode == 0

    with log.open("w") as output:
        process = subprocess.Popen(["quickshell", "--path", str(entry)], env=env,
                                   stdout=output, stderr=output, umask=0o077)
        try:
            dark = wait(lambda s: s["available"] and s["snapshot"] and s["snapshot"]["mode"] == "dark")
            assert not dark["writeError"]
            assert shared.stat().st_mode & 0o777 == 0o640
            # Explicit manual commands through the production state owner.
            broadcast("light")
            light = wait(lambda s: s["snapshot"] and s["snapshot"]["mode"] == "light")
            assert light["snapshot"]["colors"]["backgroundSurface"] != dark["snapshot"]["colors"]["backgroundSurface"]
            assert ipc("setMode", "true").returncode == 0
            wait(lambda s: s["snapshot"] and s["snapshot"]["mode"] == "dark")
            # Wallpaper events never rewrite appearance, and mode events never copy images.
            appearance_stamp = shared.stat().st_mtime_ns
            assert ipc("setWallpaper", str(image_file), "cover").returncode == 0
            wall = wait(lambda s: s["wallpaperReady"])
            assert not wall["wallpaperError"]
            assert shared.stat().st_mtime_ns == appearance_stamp
            asset = shared.parent / wall["wallpaperSnapshot"]["image"]
            asset_stamp = asset.stat().st_mtime_ns
            descriptor_stamp = wallpaper_file.stat().st_mtime_ns
            broadcast("light")
            wait(lambda s: s["snapshot"]["mode"] == "light")
            assert asset.stat().st_mtime_ns == asset_stamp
            assert wallpaper_file.stat().st_mtime_ns == descriptor_stamp
            assert ipc("setWallpaper", str(image_file), "contain").returncode == 0
            wait(lambda s: s["wallpaperSnapshot"]["fit"] == "contain")
            assert asset.stat().st_mtime_ns == asset_stamp
            # A source replacement is an event too; no polling or selection change.
            temp_image = image_file.with_suffix(".tmp")
            temp_image.write_bytes(png(120, 50, 80))
            temp_image.replace(image_file)
            wait(lambda s: s["wallpaperSnapshot"]["revision"] != wall["wallpaperSnapshot"]["revision"] and s["wallpaperReady"])
            broadcast("dark")
            wait(lambda s: s["snapshot"]["mode"] == "dark")
            # Reader retains valid colours for invalid JSON/schema/version/colour.
            for invalid in ("{", '{"version":2}', json.dumps(dict(dark["snapshot"], mode="auto"))):
                replace(invalid)
                rejected = wait(lambda s: bool(s["readError"]))
                assert rejected["snapshot"] == dark["snapshot"]
                replace(json.dumps(dark["snapshot"]))
                wait(lambda s: not s["readError"])
            custom = json.loads(json.dumps(light["snapshot"]))
            custom["colors"]["accent"] = "#aabbcc"
            replace(json.dumps(custom))
            wait(lambda s: s["snapshot"] == custom)
            shared.unlink()
            time.sleep(.3)
            assert json.loads(ipc("status").stdout)["snapshot"] == custom
            replace(json.dumps(custom))
            wait(lambda s: s["snapshot"] == custom)
            # Switching to an account without a published slot resets to default theme/wallpaper.
            assert ipc("setUser", "other-user").returncode == 0
            wait(lambda s: s["snapshot"] is None and not s["wallpaperReady"])
            assert ipc("setUser", "../escape").returncode == 0
            assert json.loads(ipc("status").stdout)["snapshot"] is None
            assert ipc("setUser", "fixture-user").returncode == 0
            wait(lambda s: s["snapshot"] == custom and s["wallpaperReady"])
        finally:
            process.terminate()
            process.wait(timeout=5)

    assert shared.exists(), "Snapshot must survive publisher exit"
    assert (state / "nullshell/appearance-mode").read_text().strip() == "dark"
    # Restore a persisted light choice without any external mode service.
    (state / "nullshell/appearance-mode").write_text("light\n")
    with log.open("a") as output:
        restarted = subprocess.Popen(["quickshell", "--path", str(entry)], env=env, stdout=output, stderr=output)
        try:
            wait(lambda s: s["snapshot"] and s["snapshot"]["mode"] == "light")
        finally:
            restarted.terminate()
            restarted.wait(timeout=5)
    replace(json.dumps(custom))
    # A separate late-starting consumer requires no desktop or mode provider.
    entry.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "AppearanceRules.js" as Rules
ShellRoot {
    AppearanceSnapshot {
        id: reader
        path: Rules.slotFile(Quickshell.env("NULLSHELL_APPEARANCE_DIR"), "fixture-user", "theme.json")
    }
    IpcHandler {
        target: "test"
        function status(): string { return JSON.stringify({snapshot: reader.snapshot}); }
    }
}''')
    with log.open("a") as output:
        consumer = subprocess.Popen(["quickshell", "--path", str(entry)], env=env, stdout=output, stderr=output)
        try:
            wait(lambda s: s["snapshot"] == custom)
        finally:
            consumer.terminate()
            consumer.wait(timeout=5)
    if os.environ.get("NULLSHELL_TEST_SNAPSHOT_DIR"):
        samples = Path(os.environ["NULLSHELL_TEST_SNAPSHOT_DIR"])
        samples.mkdir(parents=True, exist_ok=True)
        (samples / "dark.json").write_text(json.dumps(dark["snapshot"]))
        (samples / "light.json").write_text(json.dumps(light["snapshot"]))
    # Export rejects malformed/oversized input without overwriting valid data.
    before = shared.read_bytes()
    for invalid in (b"{}", b"x" * 16385):
        result = subprocess.run([str(HELPER), "appearance-export", str(shared)], input=invalid, capture_output=True)
        assert result.returncode != 0 and shared.read_bytes() == before
    # A missing shared destination never causes privileged directory creation;
    # explicit paths report failure, while --optional skips unprovisioned slots cleanly.
    result = subprocess.run([str(HELPER), "appearance-export", str(base / "missing/theme.json")],
                            input=before, capture_output=True)
    assert result.returncode != 0 and shared.read_bytes() == before
    optional = subprocess.run([str(HELPER), "appearance-export", "--optional", str(base / "missing/theme.json")],
                              input=before, capture_output=True)
    assert optional.returncode == 0 and not (base / "missing").exists()
    text = "\n".join(line for line in log.read_text().splitlines() if "Appearance snapshot:" not in line)
    assert not any(x in text for x in ("ReferenceError", "TypeError", "SyntaxError", "Cannot assign")), text
print("Appearance manual persistence, relocated paths, atomic permissions, validation and recovery passed")

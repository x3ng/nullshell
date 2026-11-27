"""Display placement rules, exercised without a compositor or the Rust helper."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


HERE = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="ns-geometry-", dir="/tmp") as directory:
    base = Path(directory)
    (base / "components").mkdir()
    (base / "runtime").mkdir(mode=0o700)
    shutil.copy2(HERE / "display_geometry.qml", base / "shell.qml")
    shutil.copy2(HERE.parent / "components/DisplayGeometry.js", base / "components/DisplayGeometry.js")
    entry = str(base / "shell.qml")
    env = dict(os.environ, HOME=str(base), XDG_CONFIG_HOME=str(base / "config"),
        XDG_RUNTIME_DIR=str(base / "runtime"), XDG_CACHE_HOME=str(base / "cache"),
        XDG_STATE_HOME=str(base / "state"), QT_QPA_PLATFORM="offscreen",
        QT_QUICK_BACKEND="software",
        DBUS_SESSION_BUS_ADDRESS=f"unix:path={base}/no-session",
        DBUS_SYSTEM_BUS_ADDRESS=f"unix:path={base}/no-system")
    for name in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
        env.pop(name, None)
    log = base / "qml.log"
    with log.open("w") as output:
        process = subprocess.Popen(["quickshell", "--path", entry], env=env,
            stdin=subprocess.DEVNULL, stdout=output, stderr=output)
        try:
            deadline = time.monotonic() + 20
            last = None
            while time.monotonic() < deadline:
                response = subprocess.run(["quickshell", "ipc", "--path", entry, "call", "geometry", "status"],
                    env=env, capture_output=True, text=True, timeout=3)
                if response.returncode == 0:
                    last = json.loads(response.stdout)
                    break
                time.sleep(0.2)
            assert last is not None, f"Display geometry status never became available; QML: {log.read_text()}"
            assert not last["failures"], "Rejected placement case: " + ", ".join(last["failures"])
            assert last["cases"] >= 30, f"Expected the full placement matrix, ran {last['cases']} cases"
            print(f"Display geometry: {last['cases']} placement cases passed")
        finally:
            process.terminate()
            process.wait(timeout=10)

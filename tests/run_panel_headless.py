"""Run the production panel preview on an isolated headless labwc compositor.

Requires labwc with the wlroots headless backend, pixman and software OpenGL. Arguments
are forwarded to test_panel_preview.py. No host input, services or windows are used.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

with tempfile.TemporaryDirectory(prefix="ns-panel-", dir="/tmp") as directory:
    base = Path(directory)
    runtime = base / "runtime"
    runtime.mkdir(mode=0o700)
    config = base / "labwc"
    config.mkdir()
    (config / "rc.xml").write_text('<labwc_config><core><gap>0</gap></core></labwc_config>')
    env = dict(os.environ, HOME=str(base), XDG_CONFIG_HOME=str(base / "config"),
        XDG_CACHE_HOME=str(base / "cache"), XDG_STATE_HOME=str(base / "state"),
        XDG_RUNTIME_DIR=str(runtime), WLR_BACKENDS="headless", WLR_HEADLESS_OUTPUTS="1", WLR_RENDERER="pixman",
        LIBGL_ALWAYS_SOFTWARE="1", QSG_RHI_BACKEND="opengl", NULLSHELL_PREVIEW_EXCLUSIVE_KEYBOARD="1",
        DBUS_SESSION_BUS_ADDRESS="unix:path=" + str(base / "no-session-bus"),
        DBUS_SYSTEM_BUS_ADDRESS="unix:path=" + str(base / "no-system-bus"))
    for key in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "QT_QPA_PLATFORM", "QT_QUICK_BACKEND"):
        env.pop(key, None)
    log = base / "compositor.log"
    with log.open("w") as output:
        compositor = subprocess.Popen(["labwc", "--config-dir", str(config)], env=env,
            stdin=subprocess.DEVNULL, stdout=output, stderr=output)
        try:
            for _ in range(200):
                sockets = [p for p in runtime.glob("wayland-*") if p.is_socket()]
                if sockets: break
                if compositor.poll() is not None: raise RuntimeError(log.read_text())
                time.sleep(.1)
            else: raise RuntimeError("Headless compositor did not start\n" + log.read_text())
            env["WAYLAND_DISPLAY"] = sockets[0].name
            subprocess.run([sys.executable, str(Path(__file__).with_name("test_panel_preview.py")), *sys.argv[1:]],
                env=env, check=True, timeout=240)
        finally:
            compositor.terminate()
            try: compositor.wait(timeout=5)
            except subprocess.TimeoutExpired:
                compositor.kill(); compositor.wait(timeout=5)

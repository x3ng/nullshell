"""Exercise shared login information in an ordinary preview, without PAM or locking."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--screenshots", type=Path, required=True)
parser.add_argument("--keyboard", action="store_true")
args = parser.parse_args()
args.screenshots.mkdir(parents=True, exist_ok=True)
entry = Path(__file__).resolve().parents[1] / "preview.qml"
ipc = ["quickshell", "ipc", "--path", str(entry), "call", "preview"]

def call(*arguments):
    return subprocess.check_output(ipc + list(arguments), text=True, timeout=5).strip()

with tempfile.TemporaryDirectory(prefix="ns-login-info-") as directory:
    log = Path(directory) / "preview.log"
    with log.open("w") as stream:
        process = subprocess.Popen(["quickshell", "--path", str(entry)], stdout=stream, stderr=stream)
    try:
        for _ in range(100):
            probe = subprocess.run(ipc + ["infoStatus"], capture_output=True, text=True, timeout=3)
            if probe.returncode == 0:
                break
            if process.poll() is not None:
                raise AssertionError(log.read_text())
            time.sleep(.1)
        else:
            raise AssertionError("Preview did not start")
        for lock in ["true", "false"]:
            call("mode", lock)
            for light in ["false", "true"]:
                call("light", light)
                for width, height in [(1100, 640), (480, 640), (400, 640)]:
                    call("size", str(width), str(height))
                    time.sleep(.4)
                    for scenario in ["normal", "low", "full", "missing", "long", "cage"]:
                        call("info", scenario)
                        time.sleep(.15)
                        state = json.loads(call("infoStatus"))
                        assert state["caps"] == (scenario in ["low", "long"])
                        assert state["low"] == (scenario == "low")
                        assert bool(state["keyboard"]) == (scenario not in ["missing", "cage"])
                        assert bool(state["battery"]) == (scenario != "missing")
                        path = args.screenshots / f"{'lock' if lock == 'true' else 'greeter'}-{width}-{light}-{scenario}.png"
                        path.unlink(missing_ok=True)
                        assert call("capture", str(path)) == "true"
                        from PIL import Image
                        for _ in range(30):
                            try:
                                with Image.open(path) as image:
                                    image.load()
                                    assert image.width == state["width"] and image.height == state["height"]
                                    assert 400 <= image.width <= width and 500 <= image.height <= height, (state, width, height)
                                break
                            except (OSError, ValueError):
                                time.sleep(.1)
                        else:
                            raise AssertionError("Capture did not finish")
        if args.keyboard:
            before = json.loads(call("infoStatus"))["keyboardRefreshes"]
            subprocess.run(["wtype", "-k", "Caps_Lock"], check=True, timeout=5)
            time.sleep(.2)
            assert json.loads(call("infoStatus"))["keyboardRefreshes"] > before
            call("mode", "false")
            call("size", "1100", "640")
            call("light", "true")
            call("power", "true")
            time.sleep(.2)
            assert json.loads(call("infoStatus"))["powerOpen"]
            power_shot = args.screenshots / "greeter-1100-true-power.png"
            assert call("capture", str(power_shot)) == "true"
            time.sleep(.15)
            subprocess.run(["wtype", "-k", "Escape"], check=True, timeout=5)
            time.sleep(.2)
            assert not json.loads(call("infoStatus"))["powerOpen"]
        call("quit")
        process.wait(timeout=5)
        assert process.returncode == 0
        assert not re.search(r"TypeError|ReferenceError|SyntaxError|Cannot assign|Binding loop", log.read_text()), log.read_text()
        print("Login information: lock/greeter, palettes, sizes and missing-data states passed")
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        (args.screenshots / "preview.log").write_text(log.read_text())

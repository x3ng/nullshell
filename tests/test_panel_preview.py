"""Portable Wayland preview checks. No Nix imports or host service changes.

Requires Python 3 and Quickshell on PATH and a running Wayland compositor.
Optional --keyboard uses wtype; --screenshots uses grim. Prefer a nested/test
compositor for keyboard injection. The process started here is always cleaned up.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qml", type=Path, default=Path(__file__).resolve().parents[1] / "qml/preview-panel.qml")
    parser.add_argument("--screenshots", type=Path)
    parser.add_argument("--keyboard", action="store_true")
    args = parser.parse_args()
    if not os.environ.get("WAYLAND_DISPLAY"):
        parser.error("A Wayland session is required; no Nix environment is required")
    entry = str(args.qml.resolve(strict=True))
    ipc = ["quickshell", "ipc", "--path", entry, "call", "preview"]
    existing = subprocess.run(ipc + ["status"], capture_output=True, timeout=3)
    if existing.returncode == 0:
        parser.error("This source preview is already running; close it before running the test")
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)

    def call(*arguments):
        return subprocess.check_output(ipc + list(arguments), text=True, timeout=5).strip()

    def state():
        return json.loads(call("status"))

    def settle():
        previous = None
        for _ in range(30):
            value = state()
            geometry = value["card"]
            if geometry == previous and geometry["height"] > 0:
                time.sleep(0.3)
                return state()
            previous = geometry
            time.sleep(0.25)
        raise AssertionError("Panel geometry did not settle")

    def screenshot(name):
        if args.screenshots:
            subprocess.run(["grim", str(args.screenshots / (name + ".png"))], check=True, timeout=10)

    with tempfile.TemporaryDirectory(prefix="nullshell-preview-test-") as temporary:
        log = Path(temporary) / "preview.log"
        with log.open("w") as output:
            process = subprocess.Popen(["quickshell", "--path", entry], stdout=output, stderr=output)
        try:
            for _ in range(100):
                if process.poll() is not None:
                    raise AssertionError("Preview exited during startup")
                probe = subprocess.run(ipc + ["status"], text=True, capture_output=True, timeout=3)
                if probe.returncode == 0 and json.loads(probe.stdout)["open"]:
                    break
                time.sleep(0.1)
            else:
                raise AssertionError("Preview IPC did not become ready")
            settle()
            screenshot("normal")
            for scenario in ["empty", "crowded", "media", "normal"]:
                assert call("scenario", scenario) == "true"
                for page in ["overview", "wifi", "bluetooth", "audio", "notifications", "desktop"]:
                    call("page", page)
                    current = settle()
                    expected = page if page in ["overview", "desktop"] else "detail:" + page
                    assert current["page"] == expected and current["open"], current
                    assert current["card"]["width"] > 0
            call("scenario", "crowded")
            call("search", "terminal")
            before = settle()
            assert before["results"] > 0
            if args.keyboard:
                subprocess.run(["wtype", "-s", "200", "-M", "ctrl", "-k", "n", "-m", "ctrl"], check=True, timeout=5)
                before = state()
                assert before["selectedIndex"] == 1, before
            call("tick")
            changed = settle()
            assert changed["results"] == before["results"]
            assert changed["selectedKey"] == before["selectedKey"]
            call("action", "keep-awake")
            assert not state()["keepAwake"]
            call("width", "440")
            call("light", "true")
            call("page", "overview")
            narrow = settle()
            assert narrow["card"]["width"] == 440 and not narrow["dark"], narrow
            screenshot("narrow-light")
            call("close")
            assert not state()["open"]
            call("openPanel")
            assert state()["open"]
            call("quit")
            process.wait(timeout=5)
            assert process.returncode == 0
            errors = re.findall(r"^.*(?:TypeError|ReferenceError|SyntaxError|Cannot assign|not a function|failed to load|Binding loop).*$", log.read_text(), re.MULTILINE | re.IGNORECASE)
            assert not errors, "\n".join(errors)
            print("Panel preview: scenarios, routes, resizing, selection and cleanup passed")
        except BaseException:
            print(log.read_text())
            raise
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            if args.screenshots:
                (args.screenshots / "preview.log").write_text(log.read_text())


if __name__ == "__main__":
    main()

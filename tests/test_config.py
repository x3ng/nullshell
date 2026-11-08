"""Exercise real FileView reloads in an isolated Quickshell process."""
import json
import os
from pathlib import Path
import subprocess
import sys
import shutil
import tempfile
import time

# Quickshell scans only the config subtree. Stage the actual two source modules
# with the test entrypoint instead of importing outside its configuration root.
resources = tempfile.TemporaryDirectory(prefix="nullshell-config-test-")
staged = Path(resources.name)
source = Path(__file__).resolve().parent
shutil.copy2(source / "config.qml", staged / "config.qml")
for name in ("ShellConfig.qml", "ConfigRules.js"):
    shutil.copy2(source.parent / name, staged / name)
entry = str(staged / "config.qml")
config = Path(os.environ["XDG_CONFIG_HOME"]) / "nullshell/config.json"
config.parent.mkdir(parents=True, exist_ok=True)
log = Path(sys.argv[1])


def write(value):
    temp = config.with_suffix(".tmp")
    temp.write_text(value)
    temp.replace(config)


def wait_for(predicate):
    deadline = time.monotonic() + 8
    last = None
    while time.monotonic() < deadline:
        response = subprocess.run(
            ["quickshell", "ipc", "--path", entry, "call", "config", "status"],
            capture_output=True, text=True, timeout=2,
        )
        if response.returncode == 0:
            try:
                last = json.loads(response.stdout)
            except json.JSONDecodeError:
                raise AssertionError(f"Unexpected IPC output: {response.stdout!r}; stderr: {response.stderr!r}; QML: {log.read_text()}")
            if predicate(last):
                return last
        time.sleep(0.1)
    raise AssertionError(f"Configuration did not reach expected state: {last}; "
                         f"IPC: {response.stderr}; QML: {log.read_text()}")


with log.open("w") as output:
    process = subprocess.Popen(["quickshell", "--path", entry], stdout=output, stderr=output)
    try:
        initial = wait_for(lambda s: s["ready"])
        assert not initial["error"]
        assert initial["values"]["idle"]["lockSeconds"] == 300
        write('{"version":1,"terminal":["foot","--"],"idle":{"lockSeconds":400}}')
        valid = wait_for(lambda s: s["values"]["terminal"] == ["foot", "--"])
        assert valid["values"]["idle"]["lockSeconds"] == 400
        for malformed in ('{', '{"version":1,"idle":{"lockSeconds":1}}'):
            write(malformed)
            invalid = wait_for(lambda s: bool(s["error"]))
            assert invalid["values"] == valid["values"]
            # Recover between invalid writes so each rejection is observed.
            write(json.dumps(valid["values"]))
            wait_for(lambda s: not s["error"])
        write('{"version":1}')
        reset = wait_for(lambda s: s["values"] == initial["values"] and not s["error"])
        assert reset["ready"]
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
text = log.read_text()
assert "CONFIG_RULES_PASSED" in text, text
assert not any(word in text for word in ("ReferenceError", "TypeError", "SyntaxError")), text
resources.cleanup()
print("Config validation, missing defaults, atomic hot reload, rejection and recovery passed")

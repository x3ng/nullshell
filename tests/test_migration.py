"""Legacy import must be one-time, non-destructive and concurrency-safe."""
import os
from pathlib import Path
import subprocess
import tempfile

script = Path(__file__).resolve().parents[1] / "bin/nullshell-migrate-state"
with tempfile.TemporaryDirectory(prefix="nullshell-migration-") as temp:
    root = Path(temp)
    env = dict(os.environ, HOME=temp, XDG_STATE_HOME=str(root / "state"), XDG_CONFIG_HOME=str(root / "config"))
    old = root / "state/quickshell"
    new = root / "state/nullshell"
    old.mkdir(parents=True)
    new.mkdir(parents=True)
    (old / "keep-awake").write_text("true\n")
    (old / "notifications.json").write_text('{"history":[]}')
    (new / "notifications.json").write_text('{"existing":true}')
    processes = [subprocess.Popen(["sh", str(script)], env=env) for _ in range(3)]
    assert all(p.wait(timeout=10) == 0 for p in processes)
    assert (new / "keep-awake").read_text() == "true\n"
    assert (old / "keep-awake").read_text() == "true\n"
    assert (new / "notifications.json").read_text() == '{"existing":true}'
    assert (new / "keep-awake").stat().st_mode & 0o777 == 0o600
    (new / "keep-awake").unlink()
    subprocess.run(["sh", str(script)], env=env, check=True)
    assert not (new / "keep-awake").exists(), "Cleared state must not be re-imported"
    assert not list(new.glob("*.import.*"))
print("Legacy migration concurrency, ownership and one-time import passed")

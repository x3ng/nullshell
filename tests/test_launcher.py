"""Check checkout/package routing without starting a desktop or authenticating."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='nullshell-routing-') as tmp:
    root = Path(tmp)
    install = root / 'installed'
    (install / 'bin').mkdir(parents=True)
    for name in ('nullshell', 'nullshell-lock', 'nullshell-migrate-state'):
        shutil.copy2(source / 'bin' / name, install / 'bin' / name)
    # Side-effect-free probe replacing only external commands.
    probe = root / 'tools'
    probe.mkdir()
    for name in ('quickshell', 'hypridle'):
        path = probe / name
        path.write_text('#!/usr/bin/env python3\nimport json,os,sys\nprint(json.dumps({"args":sys.argv[1:],"data":os.environ.get("NULLSHELL_DATA_DIR")}))\n')
        path.chmod(0o755)
    env = {k: v for k, v in os.environ.items() if not k.startswith('NULLSHELL_')}
    env.update(HOME=str(root / 'home'), XDG_CONFIG_HOME=str(root / 'config'),
               XDG_STATE_HOME=str(root / 'state'), PATH=str(probe) + os.pathsep + os.environ['PATH'])
    local = root / 'config/quickshell/nullshell'
    for name in ('shell.qml', 'preview-panel.qml', 'lock/shell.qml', 'polkit/shell.qml', 'greeter/shell.qml'):
        path = local / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch()

    def run(*args, extra=None, launcher=None, success=True):
        result = subprocess.run([str(launcher or install / 'bin/nullshell'), *args],
                                env=env | (extra or {}), text=True, capture_output=True, timeout=5)
        assert (result.returncode == 0) == success, result.stderr
        return json.loads(result.stdout) if success else result.stderr

    for mode, entry in [('desktop', 'shell.qml'), ('locker', 'lock/shell.qml'),
                        ('polkit', 'polkit/shell.qml'), ('preview-panel', 'preview-panel.qml')]:
        value = run(mode)
        assert value['args'] == ['--path', str(local / entry)]
        assert value['data'] == str(local)
    for mode, entry in [('desktop', 'shell.qml'), ('locker', 'lock/shell.qml'), ('polkit', 'polkit/shell.qml')]:
        value = run('ipc', mode, 'call', 'probe', 'status')
        assert value['args'] == ['ipc', '--path', str(local / entry), 'call', 'probe', 'status']
    # A greeter must never accidentally load an editable user's checkout.
    assert 'Missing nullshell resource' in run('greeter', success=False)
    packaged = root / 'snapshot'
    (packaged / 'greeter').mkdir(parents=True)
    (packaged / 'greeter/shell.qml').touch()
    value = run('greeter', extra={'NULLSHELL_PACKAGED_DATA_DIR': str(packaged)})
    assert value['args'] == ['--path', str(packaged / 'greeter/shell.qml')]
    link = root / 'checkout with spaces'
    link.symlink_to(local, target_is_directory=True)
    assert run('preview-panel', extra={'NULLSHELL_CONFIG_DIR': str(link)})['data'] == str(local)
    # Explicit source previews remain usable with a packaged runtime.
    assert run('preview-panel', extra={'NULLSHELL_DATA_DIR': str(source)})['data'] == str(source)
    assert run('preview-panel', launcher=source / 'bin/nullshell')['data'] == str(source)
    sleep = source / 'integration/hypridle.conf'
    assert run('sleep-bridge', extra={'NULLSHELL_SLEEP_CONFIG': str(sleep)})['args'] == ['--config', str(sleep)]
    (local / 'shell.qml').unlink()
    assert 'Missing nullshell resource' in run('desktop', success=False)
print('Launcher: source, XDG, packaged greeter, IPC, canonical paths and missing checkout passed')

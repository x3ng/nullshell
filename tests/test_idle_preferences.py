"""Real QML idle preference store, without a compositor or idle actions."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='ns-idle-') as temp:
    base = Path(temp)
    runtime = base / 'runtime'
    runtime.mkdir(mode=0o700)
    for module in ('IdlePreferences.qml', 'ConfigRules.js'):
        shutil.copy2(ROOT / module, base / module)
    entry = base / 'shell.qml'
    entry.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    IdlePreferences { id: idle }
    IpcHandler {
        target: "idleTest"
        function status(): string { return JSON.stringify({ready:idle.ready,saving:idle.saving,
            deadlines:idle.values, overridden:idle.overridden, error:idle.error}); }
        function apply(value: string): bool { return idle.store(JSON.parse(value)); }
        function defaults(value: string): void { idle.configured = JSON.parse(value); }
    }
}''')
    env = dict(os.environ, HOME=temp, XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(base / 'config'),
               XDG_CACHE_HOME=str(base / 'cache'), XDG_STATE_HOME=str(base / 'state'),
               QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
               DBUS_SESSION_BUS_ADDRESS=f'unix:path={base}/no-session', DBUS_SYSTEM_BUS_ADDRESS=f'unix:path={base}/no-system')
    for key in ('WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
        env.pop(key, None)
    state = base / 'state/nullshell/idle-policy.json'
    ipc = ['quickshell', 'ipc', '--path', str(entry), 'call', 'idleTest']
    log = base / 'shell.log'
    package = dict(dimSeconds=150, lockSeconds=300, displayOffSeconds=600)
    chosen = dict(dimSeconds=60, lockSeconds=120, displayOffSeconds=180)
    configured = dict(dimSeconds=90, lockSeconds=180, displayOffSeconds=240)

    def call(*args, check=True):
        return subprocess.run(ipc + list(args), env=env, check=check, capture_output=True, text=True, timeout=4)

    def wait(predicate):
        last = None
        end = time.monotonic() + 5
        while time.monotonic() < end:
            result = call('status', check=False)
            if result.returncode == 0:
                last = json.loads(result.stdout)
                if predicate(last): return last
            time.sleep(.08)
        raise AssertionError(f'{last}\n{log.read_text()}')

    def start():
        with log.open('a') as out:
            child = subprocess.Popen(['quickshell', '--path', str(entry)], env=env, stdout=out, stderr=out)
        wait(lambda s: s['ready'])
        return child

    def stop(child):
        child.terminate()
        child.wait(timeout=5)

    child = start()
    try:
        assert wait(lambda s: s['deadlines'] == package)['error'] == ''
        assert call('apply', '{"dimSeconds":200,"lockSeconds":40,"displayOffSeconds":500}').stdout.strip() == 'false'
        assert wait(lambda s: bool(s['error']))['deadlines'] == package
        assert not state.exists()
        assert call('apply', json.dumps(chosen)).stdout.strip() == 'true'
        wait(lambda s: s['overridden'] and not s['saving'] and s['deadlines'] == chosen)
        assert json.loads(state.read_text()) == {'version':1, 'idle':chosen}
    finally:
        stop(child)

    child = start()
    try:
        wait(lambda s: s['deadlines'] == chosen and s['overridden'])
        call('defaults', json.dumps(configured))
        assert wait(lambda s: s['deadlines'] == chosen)['overridden']
        assert call('apply', 'null').stdout.strip() == 'true'
        wait(lambda s: s['deadlines'] == configured and not s['overridden'])
        assert json.loads(state.read_text()) == {'version':1, 'idle':None}
        state.unlink()
        state.mkdir()
        assert call('apply', json.dumps(chosen)).stdout.strip() == 'true'
        assert wait(lambda s: not s['saving'] and 'Could not save' in s['error'])['deadlines'] == configured
    finally:
        stop(child)

    state.rmdir()
    state.write_text('{"version":1,"idle":{"dimSeconds":1}}')
    child = start()
    try:
        assert wait(lambda s: 'Could not read' in s['error'])['deadlines'] == package
    finally:
        stop(child)

    assert not any(word in log.read_text() for word in ('TypeError', 'ReferenceError', 'SyntaxError'))

print('Idle preferences: defaults, validation, persistence across restart, reset, and write failure passed')

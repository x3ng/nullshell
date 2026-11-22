"""Real Rust planner and Quickshell policy, isolated from the host compositor."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
HELPER = Path(sys.argv[1]).resolve()


def output(key, name, width, height, refresh, **changes):
    return dict(key=key, name=name, enabled=True, width=width, height=height,
                refresh=refresh, **changes)


def live(name, make, model, serial, width, height, refresh, x=0, y=0, mirror='none'):
    return dict(name=name, make=make, model=model, serial=serial, width=width, height=height,
                refreshRate=refresh, x=x, y=y, scale=1, transform=0, disabled=False,
                availableModes=[f'{width}x{height}@{refresh}Hz'], mirrorOf=mirror)


with tempfile.TemporaryDirectory(prefix='ns-displays-') as directory:
    base = Path(directory)
    for name in ('runtime', 'bin', 'adapters', 'components'):
        (base / name).mkdir(mode=0o700)
    for name in ('DisplayProfiles.qml', 'adapters/DisplayTrial.lua', 'components/HyprlandControlCommands.js'):
        shutil.copy2(ROOT / name, base / name)
    (base / 'bin/nullshell-helper').symlink_to(HELPER)
    env = dict(os.environ, HOME=str(base), XDG_CONFIG_HOME=str(base / 'config'),
               XDG_RUNTIME_DIR=str(base / 'runtime'), XDG_CACHE_HOME=str(base / 'cache'),
               XDG_STATE_HOME=str(base / 'state'), QT_QPA_PLATFORM='offscreen',
               QT_QUICK_BACKEND='software', HYPRLAND_INSTANCE_SIGNATURE='fixture-only',
               DBUS_SYSTEM_BUS_ADDRESS=f'unix:path={base}/no-system',
               DBUS_SESSION_BUS_ADDRESS=f'unix:path={base}/no-session',
               PATH=str(base / 'bin') + os.pathsep + os.environ['PATH'])
    for name in ('WAYLAND_DISPLAY', 'DISPLAY'):
        env.pop(name, None)

    panel = output('test|panel', 'eDP-1', 1920, 1080, 60)
    extended = output('test|external|test123', 'DP-4', 2560, 1440, 60, x=-2560)
    mirrored = dict(extended, mirror_of=panel['key'])
    auto = dict(name='extend', outputs=[panel, extended], workspaces=[
                    dict(workspace='2', output_key=extended['key'], persistent=True),
                    dict(workspace='special:fixture', output_key='')])
    profiles = [auto, dict(name='laptop', outputs=[panel]), dict(name='mirror', outputs=[panel, mirrored])]

    connected = base / 'connected.json'
    applied = base / 'applied.json'
    apply_enabled = base / 'apply-enabled'
    commands = base / 'commands'
    first = live('eDP-1', 'TEST', 'Panel', '', 1920, 1080, 60)
    external = live('HDMI-A-3', 'Test', 'External', 'TEST123', 2560, 1440, 60)

    def connect(*outputs):
        connected.write_text(json.dumps(outputs))

    def remember(outputs):
        applied.write_text(json.dumps(outputs))

    connect(first, external)
    remember([first, dict(external, x=-2560)])
    apply_enabled.touch()
    fake = base / 'bin/hyprctl'
    fake.write_text(f'''#!{sys.executable}
from pathlib import Path
import json, sys
root = Path({str(base)!r})
args = sys.argv[1:]
pending = root / 'pending'
with (root / 'commands').open('a') as log:
    print(json.dumps(args), file=log)
if args == ['-j', 'monitors', 'all']:
    outputs = json.loads((root / 'connected.json').read_text())
    if pending.exists() and (root / 'apply-enabled').exists():
        settings = {{o['name']: o for o in json.loads((root / 'applied.json').read_text())}}
        outputs = [settings.get(o['name'], o) for o in outputs]
    print(json.dumps(outputs))
elif args == ['reload']:
    pending.unlink(missing_ok=True)
    print('ok')
elif args[0] == 'eval' and '.start(' in args[1]:
    pending.touch()
    print('ok')
elif args[0] == 'eval' and '.confirm(' in args[1] and pending.exists():
    print('ok')
else:
    raise SystemExit('unexpected command')
''')
    fake.chmod(0o700)

    def run(*args, check=True):
        return subprocess.run(args, env=env, check=check, timeout=8, text=True, capture_output=True)

    config = base / 'display-profiles.json'
    native = json.dumps(dict(version=1, profiles=profiles))
    config.write_text(native)
    discovered = json.loads(run(str(HELPER), 'displays', 'outputs').stdout)
    assert discovered['outputs'][1] == dict(name='HDMI-A-3', key=extended['key'], modes=['2560x1440@60Hz'])
    plan = lambda *args: json.loads(run(str(HELPER), 'displays', 'plan', str(config), *args).stdout)
    initial = plan()
    assert initial['compatible'] == ['extend', 'mirror'] and initial['layout'] is None, initial
    layout = plan('extend')['layout']['lua']
    assert 'monitor="HDMI-A-3",default=false,persistent=true' in layout and 'special:fixture' not in layout, layout
    mirror_layout = plan('mirror')['layout']['lua']
    assert 'mirror="eDP-1"' in mirror_layout
    if os.environ.get('NULLSHELL_TEST_HYPRLAND'):
        # Parse the same generated rules using real Hyprland, without starting it.
        for name, rules in (('extend', layout), ('mirror', mirror_layout)):
            lua = base / f'{name}.lua'
            lua.write_text(rules)
            result = run(os.environ['NULLSHELL_TEST_HYPRLAND'], '--verify-config', '--config', str(lua), check=False)
            assert result.returncode == 0, result.stdout + result.stderr
    assert all(json.loads(line) == ['-j', 'monitors', 'all'] for line in commands.read_text().splitlines())
    config.write_text(native.replace('"eDP-1"', '"bad\\\";exec"'))
    assert run(str(HELPER), 'displays', 'plan', str(config), check=False).returncode != 0
    config.write_text(json.dumps(dict(version=1, profiles=[dict(auto, exec=['not supported'])])))
    assert run(str(HELPER), 'displays', 'plan', str(config), check=False).returncode != 0
    config.write_text(native)

    entry = base / 'shell.qml'
    entry.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    DisplayProfiles { id: service; file: Quickshell.shellPath("display-profiles.json") }
    IpcHandler {
        target: "displays"
        function status(): string { return service.status(); }
        function mode(value: string): void { service.mode = value; }
        function apply(name: string): bool { return service.activate(name); }
        function confirm(): bool { return service.confirm(); }
        function revert(): bool { return service.revert(); }
        function rescan(): void { service.scheduleScan(); }
    }
}''')
    log = base / 'qml.log'
    ipc = ['quickshell', 'ipc', '--path', str(entry), 'call', 'displays']

    def wait(predicate):
        deadline = time.monotonic() + 8
        last = None
        while time.monotonic() < deadline:
            reply = run(*ipc, 'status', check=False)
            if reply.returncode == 0:
                last = json.loads(reply.stdout)
                if predicate(last):
                    return last
            time.sleep(0.07)
        raise AssertionError(f'{last}\n{log.read_text()}\n{commands.read_text()}')

    with log.open('w') as out:
        child = subprocess.Popen(['quickshell', '--path', str(entry)], env=env, stdout=out, stderr=out)
        try:
            wait(lambda s: s['mode'] == 'off')
            count = len(commands.read_text().splitlines())
            assert run(*ipc, 'apply', 'extend').stdout.strip() == 'false'
            assert len(commands.read_text().splitlines()) == count
            run(*ipc, 'mode', 'manual')
            wait(lambda s: s['phase'] == 'idle' and 'extend' in s['compatible'])
            assert run(*ipc, 'apply', 'extend').stdout.strip() == 'true'
            wait(lambda s: s['phase'] == 'preview' and s['verified'])
            assert run(*ipc, 'confirm').stdout.strip() == 'true'
            wait(lambda s: s['active'] == 'extend' and s['phase'] == 'idle')
            assert run(*ipc, 'apply', 'missing').stdout.strip() == 'true'
            wait(lambda s: s['active'] == 'extend' and 'does not match' in s['error'])
            assert run(*ipc, 'revert').stdout.strip() == 'true'
            wait(lambda s: s['phase'] == 'idle' and not s['active'])

            # A valid planner selection still rolls back if the actual layout differs.
            apply_enabled.unlink()
            assert run(*ipc, 'apply', 'extend').stdout.strip() == 'true'
            wait(lambda s: s['phase'] == 'idle' and 'did not apply' in s['error'])
            assert not (base / 'pending').exists()
            apply_enabled.touch()

            run(*ipc, 'mode', 'off')
            run(*ipc, 'mode', 'manual')
            wait(lambda s: 'Multiple display profiles' in s['error'])
            connect(first)
            remember([first])
            before = len(commands.read_text().splitlines())
            run(*ipc, 'rescan')  # inject a synthetic monitor removal notification
            wait(lambda s: s['phase'] == 'idle' and s['suggested'] == 'laptop' and not s['active'])
            assert not any('.start(' in cmd for cmd in commands.read_text().splitlines()[before:])
            connect(first, external)
            run(*ipc, 'rescan')
            wait(lambda s: s['phase'] == 'idle' and not s['active'] and 'Multiple display profiles' in s['error'])
            assert not (base / 'pending').exists()
        finally:
            child.terminate()
            child.wait(timeout=5)
    assert not any(x in log.read_text() for x in ('TypeError', 'ReferenceError', 'SyntaxError', 'Cannot assign')), log.read_text()

print('Display discovery, topology matching, mirrors, workspace rules, opt-in, apply/confirm/revert and read-only suggestions passed')

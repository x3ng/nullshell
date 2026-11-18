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
    for name in ('quickshell', 'nullshell-helper'):
        path = probe / name
        path.write_text('#!/usr/bin/env python3\nimport json,os,sys\nprint(json.dumps({"args":sys.argv[1:],"data":os.environ.get("NULLSHELL_DATA_DIR")}))\n')
        path.chmod(0o755)
    env = {k: v for k, v in os.environ.items() if not k.startswith('NULLSHELL_')}
    env.update(HOME=str(root / 'home'), XDG_CONFIG_HOME=str(root / 'config'),
               XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(root), WAYLAND_DISPLAY='test-wayland', PATH=str(probe) + os.pathsep + os.environ['PATH'])
    local = root / 'config/quickshell/nullshell'
    for name in ('shell.qml', 'preview-panel.qml', 'lock/shell.qml', 'polkit/shell.qml', 'greeter.qml'):
        path = local / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch()

    def run(*args, extra=None, launcher=None, success=True):
        result = subprocess.run([str(launcher or install / 'bin/nullshell'), *args],
                                env=env | (extra or {}), text=True, capture_output=True, timeout=5)
        assert (result.returncode == 0) == success, result.stderr
        return json.loads(result.stdout) if success else result.stderr

    for mode, name in [('desktop', 'nullshell'), ('locker', 'nullshell/lock'),
                       ('polkit', 'nullshell/polkit')]:
        # Legacy path overrides must not redirect a user session.
        for extra in ({}, {'NULLSHELL_DATA_DIR': '/nonexistent', 'NULLSHELL_CONFIG_DIR': '/nonexistent'}):
            value = run(mode, extra=extra)
            assert value['args'] == ['-c', name]
        value = run('ipc', mode, 'call', 'probe', 'status')
        assert value['args'] == ['ipc', '-c', name, 'call', 'probe', 'status']
    # Region picker and encoder use fixed argv. Escape and encoder failures leave no partial captures.
    (probe / 'xdg-user-dir').write_text('#!/bin/sh\nprintf "%s\\n" "$HOME/Pictures with spaces"\n')
    (probe / 'slurp').write_text('#!/bin/sh\ncase "$PICK" in cancel) echo "selection cancelled" >&2; exit 1;; esac\necho "10,20 40x30"\n')
    (probe / 'grim').write_text('#!/bin/sh\n[ "$1" = -t ] && [ "$2" = png ] && [ "$3" = -g ] && [ "$4" = "10,20 40x30" ] || exit 1\nprintf payload > "$5"\n[ "$PICK" != fail ]\n')
    for tool in ['xdg-user-dir', 'slurp', 'grim']:
        (probe / tool).chmod(0o755)
    for mode, code in [('cancel', 2), ('fail', 1), ('ok', 0)]:
        captured = subprocess.run([str(install / 'bin/nullshell'), 'capture-region'], env=env | {'PICK': mode},
                                  capture_output=True, text=True, timeout=3)
        assert captured.returncode == code, captured
        files = list((root / 'home/Pictures with spaces/Screenshots').glob('*'))
        if mode == 'ok':
            assert files == [Path(captured.stdout.rstrip('\n'))] and files[0].read_text() == 'payload'
        else:
            assert not files and not captured.stdout
    # Native startup/IPC must not import legacy settings or write user state.
    assert not (root / 'state').exists()
    assert not (root / 'config/nullshell').exists()
    legacy = root / 'config/quickshell/wallpaper.json'
    legacy.write_text('{"wallpaper":"legacy"}\n')
    run('desktop')
    assert not (root / 'config/nullshell').exists()
    subprocess.run([str(install / 'bin/nullshell'), 'migrate-state'], env=env, check=True)
    assert (root / 'config/nullshell/wallpaper.json').read_bytes() == legacy.read_bytes()
    # A greeter must never accidentally load an editable user's checkout.
    assert 'Missing nullshell resource' in run('greeter', success=False)
    packaged = root / 'snapshot'
    (packaged / 'greeter').mkdir(parents=True)
    (packaged / 'greeter.qml').touch()
    value = run('greeter', extra={'NULLSHELL_PACKAGED_DATA_DIR': str(packaged)})
    assert value['args'] == ['--path', str(packaged / 'greeter.qml')]
    # Optional installed QML wins over the package, never over an explicit preview.
    override = root / 'managed interface'
    generation = override / '.qml.abc123'
    generation.mkdir(parents=True)
    (generation / '.in-use').touch()
    (override / '.install.lock').touch()
    (generation / 'greeter.qml').touch()
    (generation / 'greeter-interface.version').write_text('1\n')
    (override / 'current').symlink_to(generation.name)
    integration = {'NULLSHELL_PACKAGED_DATA_DIR': str(packaged), 'NULLSHELL_GREETER_OVERRIDE_DIR': str(override)}
    assert run('greeter', extra=integration)['args'] == ['--path', str(generation / 'greeter.qml')]
    assert run('greeter', extra=integration | {'NULLSHELL_DATA_DIR': str(local)})['args'] == ['--path', str(generation / 'greeter.qml')]
    (generation / 'greeter-interface.version').write_text('99\n')
    assert 'interface version' in run('greeter', extra=integration, success=False)
    (override / 'current').unlink()
    assert run('greeter', extra=integration)['args'] == ['--path', str(packaged / 'greeter.qml')]
    (override / 'current').symlink_to('../../escape')
    assert 'Invalid greeter QML pointer' in run('greeter', extra=integration, success=False)
    link = root / 'checkout with spaces'
    link.symlink_to(local, target_is_directory=True)
    assert run('preview-panel', extra={'NULLSHELL_DATA_DIR': str(link)})['args'] == ['--path', str(local / 'preview-panel.qml')]
    # Explicit source previews remain usable with a packaged runtime.
    assert run('preview-panel', extra={'NULLSHELL_DATA_DIR': str(source)})['args'] == ['--path', str(source / 'preview-panel.qml')]
    assert run('preview-panel', launcher=source / 'bin/nullshell')['args'] == ['--path', str(source / 'preview-panel.qml')]
    bridge = run('sleep-bridge')['args']
    assert bridge[0:2] == ['sleep-bridge', '--resume-command']
    assert json.loads(bridge[2]) == ['hyprctl', 'dispatch', 'hl.dsp.dpms({action = "on"})']
    assert run('sleep-bridge', extra={'NULLSHELL_SLEEP_CONFIG': '/obsolete'})['args'] == bridge
    assert 'Unknown mode' in run('session-start', success=False)
    (local / 'shell.qml').unlink()
    assert run('desktop')['args'] == ['-c', 'nullshell']
    assert 'Preview requires' in run('preview-panel', success=False)
print('Launcher: native config/IPC routing, isolated greeter and explicit previews passed')

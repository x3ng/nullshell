"""Run real display profile IPC in a Hyprland nested inside a headless Labwc.

Requires labwc, wtype, Hyprland, hyprctl and Quickshell, plus a render node and
Mesa drivers for Labwc's GLES renderer. Never reads the host compositor socket.
"""
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


def until(check, seconds=8):
    last = None
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        last = check()
        if last:
            return last
        time.sleep(0.1)
    raise AssertionError(f'Timed out waiting for {check.__name__}: {last!r}')


# Keep the runtime path short enough for Hyprland's AF_UNIX sockets.
with tempfile.TemporaryDirectory(prefix='h', dir=os.environ.get('NULLSHELL_NESTED_TMPDIR', '/tmp')) as name:
    base = Path(name)
    for part in ('labwc', 'bin', 'adapters', 'components'):
        (base / part).mkdir(mode=0o700)
    (base / 'labwc/rc.xml').write_text('<labwc_config/>')
    (base / 'hyprland.lua').write_text('hl.monitor({output="",mode="preferred",position="auto",scale=1})\n')
    for part in ('DisplayProfiles.qml', 'adapters/DisplayTrial.lua', 'components/HyprlandControlCommands.js'):
        shutil.copy2(ROOT / part, base / part)
    (base / 'bin/nullshell-helper').symlink_to(HELPER)
    entry = base / 'shell.qml'
    entry.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    DisplayProfiles { id: profiles; mode: "manual"; file: Quickshell.shellPath("profiles.json") }
    IpcHandler {
        target:"displays"
        function status(): string { return profiles.status(); }
        function apply(name: string): bool { return profiles.activate(name); }
        function confirm(): bool { return profiles.confirm(); }
        function mode(value: string): void { profiles.mode = value; }
    }
}''')
    env = dict(os.environ, HOME=name, XDG_CONFIG_HOME=name+'/config', XDG_STATE_HOME=name+'/state',
               XDG_CACHE_HOME=name+'/cache', XDG_RUNTIME_DIR=name, WLR_BACKENDS='headless',
               WLR_HEADLESS_OUTPUTS='1', WLR_RENDERER='gles2',
               WLR_RENDER_DRM_DEVICE=os.environ.get('WLR_RENDER_DRM_DEVICE', '/dev/dri/renderD128'),
               DBUS_SESSION_BUS_ADDRESS=f'unix:path={base}/no-session',
               DBUS_SYSTEM_BUS_ADDRESS=f'unix:path={base}/no-system',
               PATH=str(base / 'bin')+os.pathsep+os.environ['PATH'])
    for var in ('WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_CURRENT_DESKTOP',
                'AQ_BACKEND', 'QT_QPA_PLATFORM', 'QT_QUICK_BACKEND'):
        env.pop(var, None)
    env.setdefault('LIBGL_DRIVERS_PATH', '/run/opengl-driver/lib/dri')
    children = []

    def start(log, *args):
        stream = (base / log).open('w')
        with stream:
            child = subprocess.Popen(args, env=env, stdin=subprocess.DEVNULL, stdout=stream, stderr=stream)
        children.append(child)
        return child

    def command(*args):
        return subprocess.run(args, env=env, timeout=4, capture_output=True, text=True)

    def hypr(*args):
        return command('hyprctl', *args)

    def monitors():
        response = hypr('-j', 'monitors', 'all')
        return json.loads(response.stdout) if response.returncode == 0 and response.stdout.startswith('[') else []

    def ipc(*args):
        return command('quickshell', 'ipc', '--path', str(entry), 'call', 'displays', *args)

    def state():
        response = ipc('status')
        return json.loads(response.stdout) if response.returncode == 0 else {}

    def sockets():
        return [p.name for p in base.glob('wayland-*') if p.is_socket()]

    try:
        start('labwc.log', 'labwc', '--config-dir', str(base / 'labwc'))
        parent_socket = until(sockets)[0]
        env['WAYLAND_DISPLAY'] = parent_socket
        start('keyboard.log', 'wtype', '-s', '120000')  # feed a keyboard to the private seat only
        start('hyprland.log', 'Hyprland', '--config', str(base / 'hyprland.lua'))
        env['HYPRLAND_INSTANCE_SIGNATURE'] = until(lambda: list(base.glob('hypr/*/.socket.sock')))[0].parent.name
        env['WAYLAND_DISPLAY'] = until(lambda: [s for s in sockets() if s != parent_socket])[0]
        first = until(monitors)[0]

        def profile_output(monitor, **changes):
            return dict(dict(key=monitor['name'].lower(), name=monitor['name'], enabled=True,
                             width=monitor['width'], height=monitor['height'], refresh=monitor['refreshRate'],
                             x=monitor['x'], y=monitor['y'], scale=monitor['scale']), **changes)

        def write_profiles(profiles):
            path = base / 'profiles.json'
            tmp = path.with_suffix('.tmp')
            tmp.write_text(json.dumps(dict(version=1, profiles=profiles)))
            tmp.replace(path)

        solo = dict(name='solo', outputs=[profile_output(first, scale=1.25)])
        write_profiles([solo])
        desktop = start('shell.log', 'quickshell', '--path', str(entry))
        until(lambda: state().get('compatible') == ['solo'])
        assert ipc('apply', 'solo').stdout.strip() == 'true'
        until(lambda: state().get('verified'))
        assert monitors()[0]['scale'] == 1.25
        assert ipc('confirm').stdout.strip() == 'true'
        until(lambda: state().get('active') == 'solo')

        # Exercise the compositor watchdog, not a timer in the desktop process.
        assert ipc('apply', 'solo').stdout.strip() == 'true'
        until(lambda: state().get('verified'))
        desktop.terminate()
        desktop.wait(timeout=5)
        until(lambda: monitors() and monitors()[0]['scale'] == 1, seconds=19)

        desktop = start('shell-auto.log', 'quickshell', '--path', str(entry))
        until(lambda: state().get('mode') == 'manual')
        ipc('mode', 'auto').check_returncode()
        until(lambda: state().get('active') == 'solo')
        assert hypr('eval', '_G.nullshellTestNoReload = true').stdout.strip() == 'ok'
        desktop.terminate()
        desktop.wait(timeout=5)
        desktop = start('shell-adopt.log', 'quickshell', '--path', str(entry))
        until(lambda: state().get('mode') == 'manual')
        ipc('mode', 'auto').check_returncode()
        until(lambda: state().get('active') == 'solo')
        assert hypr('eval', 'assert(_G.nullshellTestNoReload)').stdout.strip() == 'ok', 'desktop restart reloaded Hyprland'
        response = hypr('output', 'create', 'headless', 'NULLSHELL-TEST')
        assert response.stdout.strip() == 'ok', response.stdout + response.stderr
        other = until(lambda: [m for m in monitors() if m['name'] == 'NULLSHELL-TEST'])[0]
        until(lambda: state().get('phase') == 'idle' and not state().get('active') and 'No profile' in state().get('error',''))
        duo = dict(name='dual', outputs=[profile_output(first), profile_output(other, x=first['width'])],
                   workspaces=[dict(workspace='7', output_key=other['name'].lower(), persistent=True)])
        mirror = dict(name='mirror', outputs=[profile_output(first), profile_output(other, mirror_of=first['name'].lower())])
        write_profiles([solo, duo, mirror])
        until(lambda: sorted(state().get('compatible', [])) == ['dual', 'mirror'])
        assert ipc('apply', 'dual').stdout.strip() == 'true'
        until(lambda: state().get('verified'))
        assert ipc('confirm').stdout.strip() == 'true'
        until(lambda: state().get('active') == 'dual')
        result = json.loads(hypr('-j', 'workspacerules').stdout)
        assert any(w.get('workspaceString') == '7' and w.get('monitor') == other['name'] for w in result), result
        assert ipc('apply', 'mirror').stdout.strip() == 'true'
        until(lambda: state().get('verified'))
        assert ipc('confirm').stdout.strip() == 'true'
        until(lambda: state().get('active') == 'mirror')
        assert any(m['name'] == other['name'] and m['mirrorOf'] in (first['name'], str(first['id']), first['id']) for m in monitors())
        assert not any(w.get('workspaceString') == '7' for w in json.loads(hypr('-j', 'workspacerules').stdout))
        # The Hyprland test command cannot remove a mirrored headless output by
        # name until it is again an independent output.
        assert hypr('reload').stdout.strip() == 'ok'
        until(lambda: any(m['name'] == other['name'] and m['mirrorOf'] == 'none' for m in monitors()))
        response = hypr('output', 'remove', other['name'])
        assert response.stdout.strip() == 'ok', response.stdout + response.stderr
        until(lambda: state().get('active') == 'solo')
    except BaseException:
        for log in list(base.glob('*.log')) + list(base.glob('hypr/*/hyprland.log')):
            print(log.name, log.read_text()[-3000:], file=sys.stderr)
        try:
            print('Desktop state:', state(), file=sys.stderr)
        except Exception:
            pass
        raise
    finally:
        for child in reversed(children):
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=5)

print('Nested Hyprland: apply/confirm, shell restart without compositor reload, watchdog, virtual hotplug, mirror and workspace rule passed')

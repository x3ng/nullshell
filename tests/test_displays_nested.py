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
    confirmed = base / 'hyprland-displays.lua'
    (base / 'hyprland.lua').write_text('''hl.monitor({output="",mode="preferred",position="auto",scale="auto"})
_G.nullshellDisplayStore = os.getenv("HOME") .. "/hyprland-displays.lua"
local restore = loadfile(_G.nullshellDisplayStore)
if restore then restore() end
''')
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
        function refreshEditor(): void { profiles.refreshEditor(); }
        function editorReady(): bool { return profiles.editorOutputs.length > 0; }
        function editorScale(scale: real): bool {
            return profiles.previewEditor(profiles.editorOutputs.map(output => Object.assign({}, output.current, {scale:scale})));
        }
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

    def launch_hyprland(log):
        env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
        env['WAYLAND_DISPLAY'] = parent_socket
        previous = set(base.glob('hypr/*/.socket.sock'))
        child = start(log, 'Hyprland', '--config', str(base / 'hyprland.lua'))
        env['HYPRLAND_INSTANCE_SIGNATURE'] = until(lambda: list(set(base.glob('hypr/*/.socket.sock')) - previous))[0].parent.name
        env['WAYLAND_DISPLAY'] = until(lambda: [s for s in sockets() if s != parent_socket])[0]
        until(monitors)
        return child

    def wait_scale(scale):
        return until(lambda: monitors() and monitors()[0]['scale'] == scale, seconds=19)

    def apply(name):
        assert ipc('apply', name).stdout.strip() == 'true', state()
        until(lambda: state().get('verified') and state().get('pending') == name)

    def confirm(name):
        assert ipc('confirm').stdout.strip() == 'true', state()
        until(lambda: state().get('phase') == 'idle' and state().get('active') == name)

    try:
        start('labwc.log', 'labwc', '--config-dir', str(base / 'labwc'))
        parent_socket = until(sockets)[0]
        env['WAYLAND_DISPLAY'] = parent_socket
        start('keyboard.log', 'wtype', '-s', '120000')  # feed a keyboard to the private seat only
        compositor = launch_hyprland('hyprland.log')
        first = monitors()[0]
        baseline = first['scale']
        preferred = 1.25 if baseline != 1.25 else 2
        unconfirmed = 2 if preferred != 2 else 1.25

        def profile_output(monitor, **changes):
            return dict(dict(key=monitor['name'].lower(), name=monitor['name'], enabled=True,
                             width=monitor['width'], height=monitor['height'], refresh=monitor['refreshRate'],
                             x=monitor['x'], y=monitor['y'], scale=monitor['scale']), **changes)

        def write_profiles(profiles):
            path = base / 'profiles.json'
            tmp = path.with_suffix('.tmp')
            tmp.write_text(json.dumps(dict(version=1, profiles=profiles)))
            tmp.replace(path)

        solo = dict(name='solo', outputs=[profile_output(first, scale=preferred)])
        desktop = start('shell.log', 'quickshell', '--path', str(entry))
        until(lambda: state().get('mode') == 'manual' and state().get('phase') == 'idle')
        # Start and confirm via the graphical service path with no profile file.
        ipc('refreshEditor').check_returncode()
        until(lambda: ipc('editorReady').stdout.strip() == 'true')
        assert ipc('editorScale', str(preferred)).stdout.strip() == 'true'
        until(lambda: state().get('pending') == 'Display changes' and state().get('verified'))
        assert not confirmed.exists() and not list(base.glob('hyprland-displays.lua.v1-*'))
        assert monitors()[0]['scale'] == preferred
        confirm('Display changes')
        confirmed_solo = until(lambda: list(base.glob('hyprland-displays.lua.v1-*')))[0]
        originals = (confirmed.read_bytes(), confirmed_solo.read_bytes())

        # Exercise the compositor watchdog, not a timer in the desktop process.
        ipc('refreshEditor').check_returncode()
        until(lambda: ipc('editorReady').stdout.strip() == 'true')
        assert ipc('editorScale', str(unconfirmed)).stdout.strip() == 'true'
        until(lambda: state().get('pending') == 'Display changes' and state().get('verified'))
        assert monitors()[0]['scale'] == unconfirmed
        assert (confirmed.read_bytes(), confirmed_solo.read_bytes()) == originals
        desktop.terminate()
        desktop.wait(timeout=5)
        wait_scale(preferred)
        assert (confirmed.read_bytes(), confirmed_solo.read_bytes()) == originals
        assert hypr('reload').stdout.strip() == 'ok'
        wait_scale(preferred)
        assert not state()

        compositor.terminate()
        compositor.wait(timeout=5)
        compositor = launch_hyprland('hyprland-restart.log')
        wait_scale(preferred)
        assert not state()

        response = hypr('output', 'create', 'headless', 'NULLSHELL-TEST')
        assert response.stdout.strip() == 'ok', response.stdout + response.stderr
        other = until(lambda: [m for m in monitors() if m['name'] == 'NULLSHELL-TEST'])[0]
        wait_scale(baseline)  # a new, unconfirmed topology uses static Auto
        assert confirmed_solo.read_bytes() == originals[1]

        desktop = start('shell-dual.log', 'quickshell', '--path', str(entry))
        until(lambda: state().get('mode') == 'manual')
        duo = dict(name='dual', outputs=[profile_output(first), profile_output(other, x=first['width'])],
                   workspaces=[dict(workspace='7', output_key=other['name'].lower(), persistent=True)])
        mirror = dict(name='mirror', outputs=[profile_output(first), profile_output(other, mirror_of=first['name'].lower())])
        write_profiles([solo, duo, mirror])
        until(lambda: sorted(state().get('compatible', [])) == ['dual', 'mirror'])
        apply('mirror')
        confirm('mirror')
        assert any(m['name'] == other['name'] and m['mirrorOf'] in (first['name'], str(first['id']), first['id']) for m in monitors())
        apply('dual')
        confirm('dual')
        until(lambda: any(w.get('workspaceString') == '7' and w.get('monitor') == other['name']
                         for w in json.loads(hypr('-j', 'workspacerules').stdout)))
        until(lambda: any(m['name'] == other['name'] and m['mirrorOf'] == 'none' for m in monitors()))
        assert len(list(base.glob('hyprland-displays.lua.v1-*'))) == 2
        closed = dict(name='external-only', outputs=[profile_output(first, enabled=False), profile_output(other)])
        write_profiles([solo, duo, mirror, closed])
        until(lambda: 'external-only' in state().get('compatible', []))
        apply('external-only')
        confirm('external-only')
        until(lambda: any(m['name'] == first['name'] and m['disabled'] for m in monitors()))
        desktop.terminate()
        desktop.wait(timeout=5)
        response = hypr('output', 'remove', other['name'])
        assert response.stdout.strip() == 'ok', response.stdout + response.stderr
        wait_scale(preferred)
        assert not any(w.get('workspaceString') == '7' for w in json.loads(hypr('-j', 'workspacerules').stdout))
        assert not state()
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

print('Nested Hyprland: persistent confirmation, watchdog, startup/reload and virtual hotplug without the shell, mirrors and workspace rules passed')

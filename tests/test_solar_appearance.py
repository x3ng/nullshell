"""Real offscreen QML application policy with isolated state and real solar helper."""
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
with tempfile.TemporaryDirectory(prefix='ns-solar-', dir='/tmp') as directory:
    base = Path(directory)
    source = base / 'source'
    source.mkdir()
    for name in ('Appearance.qml', 'AppearanceState.qml', 'AppearanceSchedule.qml', 'ShellConfig.qml', 'ConfigRules.js'):
        shutil.copy2(ROOT / name, source / name)
    shutil.copytree(ROOT / 'adapters', source / 'adapters')
    shutil.copytree(ROOT / 'components', source / 'components')
    adapter = source / 'adapters/SolarProvider.qml'
    adapter.chmod(0o600)
    adapter.write_text(adapter.read_text().replace('"nullshell-helper"', json.dumps(str(HELPER))))
    config = base / 'config/nullshell/config.json'
    config.parent.mkdir(parents=True)
    state = base / 'state/nullshell'
    state.mkdir(parents=True)
    runtime = base / 'runtime'
    runtime.mkdir(mode=0o700)
    def expected(longitude):
        result = subprocess.run([str(HELPER), 'solar'], input=json.dumps({'version': 1, 'latitude': 0,
            'longitude': longitude, 'timestamp': time.time()}), capture_output=True, text=True, check=True)
        return json.loads(result.stdout)['dark']
    # At the equator, opposing longitudes give different modes away from twilight.
    longitude = (180 - (time.time() % 86400) / 240) % 360 - 180
    first = expected(longitude)
    other_lon = longitude + 180 if longitude <= 0 else longitude - 180
    assert expected(other_lon) != first
    (state / 'appearance-mode').write_text('light\n' if first else 'dark\n')
    def configure(mode='solar', lon=longitude, location='fixed'):
        value = {'version': 1, 'appearance': {'mode': mode, 'location': location, 'latitude': 0, 'longitude': lon}}
        temp = config.with_suffix('.tmp')
        temp.write_text(json.dumps(value))
        temp.replace(config)
    configure()
    entry = source / 'test.qml'
    entry.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    ShellConfig { id: config }
    AppearanceState { id: appearance; settings: config.values.appearance }
    IpcHandler {
        target: "test"
        function manual(dark: bool): void { appearance.setTheme(dark); }
        function resume(): void { appearance.resumeAutomatic(); }
        function status(): string { return JSON.stringify({dark: appearance.darkMode,
            automatic: appearance.automatic, next: appearance.nextTransition,
            until: appearance.overrideUntil, error: appearance.appearanceError, configError: config.error}); }
    }
}''')
    env = dict(os.environ, HOME=str(base), XDG_STATE_HOME=str(base / 'state'), XDG_CONFIG_HOME=str(base / 'config'),
        XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(base / 'cache'), QT_QPA_PLATFORM='offscreen',
        QT_QUICK_BACKEND='software', GSETTINGS_BACKEND='keyfile', DBUS_SESSION_BUS_ADDRESS='unix:path=' + str(base / 'no-session'),
        DBUS_SYSTEM_BUS_ADDRESS='unix:path=' + str(base / 'no-system'))
    for key in ('WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'): env.pop(key, None)
    log = base / 'qml.log'
    def ipc(method, *args):
        return subprocess.run(['quickshell', 'ipc', '--path', str(entry), 'call', 'test', method, *args],
            env=env, capture_output=True, text=True, timeout=3)
    def wait(predicate):
        end = time.monotonic() + 12
        last = None
        while time.monotonic() < end:
            result = ipc('status')
            if result.returncode == 0:
                last = json.loads(result.stdout)
                if predicate(last): return last
            time.sleep(.1)
        raise AssertionError(f'{last}\n{log.read_text()}')
    with log.open('w') as output:
        def start(): return subprocess.Popen(['quickshell', '--path', str(entry)], env=env, stdout=output, stderr=output)
        child = start()
        try:
            wait(lambda s: s['dark'] == first and s['next'] is not None and not s['error'])
            ipc('manual', 'false' if first else 'true')
            manual = wait(lambda s: s['dark'] != first and s['until'] > time.time())
            child.terminate(); child.wait(timeout=5)
            child = start()
            wait(lambda s: s['dark'] != first and s['until'] == manual['until'] and s['next'] is not None)
            ipc('resume')
            wait(lambda s: s['dark'] == first and s['until'] == 0)
            ipc('manual', 'false' if first else 'true')
            wait(lambda s: s['until'] > time.time())
            child.terminate(); child.wait(timeout=5)
            (state / 'appearance-override.json').write_text(json.dumps({'version': 1, 'until': time.time() - 1}))
            child = start()
            wait(lambda s: s['dark'] == first and s['until'] == 0 and s['next'] is not None)
            configure(lon=other_lon)
            wait(lambda s: s['dark'] != first and s['next'] is not None)
            configure(mode='manual')
            wait(lambda s: not s['automatic'])
            ipc('manual', 'true' if first else 'false')
            wait(lambda s: s['dark'] == first)
            configure(location='geoclue')
            wait(lambda s: s['automatic'] and 'Location unavailable' in s['error'] and s['dark'] == first)
            configure()
            wait(lambda s: not s['error'] and s['next'] is not None)
        finally:
            child.terminate(); child.wait(timeout=5)
    text = log.read_text()
    assert not any(x in text for x in ('ReferenceError', 'TypeError', 'SyntaxError', 'Cannot assign')), text
print('Solar QML policy, persistence, manual override/restart/resume, config reload and location failure passed')

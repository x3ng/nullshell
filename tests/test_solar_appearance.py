"""Real offscreen QML and helper with timezone and BeaconDB fixtures."""
import json
import math
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
    for name in ('Appearance.qml', 'AppearanceState.qml', 'AppearanceSchedule.qml', 'AppearancePreferences.qml', 'ShellConfig.qml', 'ConfigRules.js'):
        shutil.copy2(ROOT / name, source / name)
    shutil.copytree(ROOT / 'adapters', source / 'adapters')
    shutil.copytree(ROOT / 'components', source / 'components')
    location = base / 'location.json'
    location_calls = base / 'location.calls'
    curl = base / 'curl'
    curl.write_text(f'''#!{sys.executable}
from pathlib import Path
import sys
with Path({str(location_calls)!r}).open('a') as log:
    print(repr(sys.argv[1:]), file=log)
assert sys.argv[1] == '--disable'
assert sys.argv[-4:] == ['--data-binary', '{{}}', '--url', 'https://api.beacondb.net/v1/geolocate']
assert '--location' not in sys.argv
fixture = Path({str(location)!r})
if not fixture.exists():
    sys.exit(28)
print(fixture.read_text())
sys.stdout.write('200')
''')
    curl.chmod(0o700)
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
        now = time.time()
        t = (now / 86400.0 + 2440587.5 - 2451545.0) / 36525.0
        l = (280.46646 + t * (36000.76983 + 0.0003032 * t)) % 360.0
        m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        c = (math.sin(math.radians(m)) * (1.914602 - t * (0.004817 + 0.000014 * t))
             + math.sin(math.radians(2.0 * m)) * (0.019993 - 0.000101 * t)
             + math.sin(math.radians(3.0 * m)) * 0.000289)
        omega = 125.04 - 1934.136 * t
        lam = l + c - 0.00569 - 0.00478 * math.sin(math.radians(omega))
        eps = 23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - 0.001813 * t))) / 60.0) / 60.0 + 0.00256 * math.cos(math.radians(omega))
        decl = math.asin(math.sin(math.radians(eps)) * math.sin(math.radians(lam)))
        y = math.tan(math.radians(eps) / 2.0) ** 2
        eq = math.degrees(4.0 * (y * math.sin(math.radians(2.0 * l)) - 2.0 * e * math.sin(math.radians(m))
             + 4.0 * e * y * math.sin(math.radians(m)) * math.cos(math.radians(2.0 * l))
             - 0.5 * y * y * math.sin(math.radians(4.0 * l)) - 1.25 * e * e * math.sin(math.radians(2.0 * m))))
        hour = ((now % 86400.0) / 60.0 + eq + 4.0 * longitude) % 1440.0 / 4.0 - 180.0
        return math.cos(decl) * math.cos(math.radians(hour)) < math.sin(math.radians(-0.833))
    # At the equator, opposing longitudes give different modes away from twilight.
    longitude = (180 - (time.time() % 86400) / 240) % 360 - 180
    first = expected(longitude)
    other_lon = longitude + 180 if longitude <= 0 else longitude - 180
    assert expected(other_lon) != first
    tzdata = base / 'tzdata'
    tzdata.mkdir()
    def set_zone(lon):
        degrees = round(lon)
        (tzdata / 'zone.tab').write_text(f'XX\t+0000{degrees:+04d}00\tTest/Local\n')
    set_zone(longitude)
    (state / 'appearance-mode').write_text('light\n' if first else 'dark\n')
    def configure(mode='solar', lon=longitude, location='fixed'):
        value = {'version': 1, 'appearance': {'mode': mode, 'location': location,
            'latitude': None if lon is None else 0, 'longitude': lon}}
        temp = config.with_suffix('.tmp')
        temp.write_text(json.dumps(value))
        temp.replace(config)
    config.write_text('{"version":1}')
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
        function select(mode: string): bool { return appearance.selectMode(mode); }
        function useIp(): bool { return appearance.useIpLocation(); }
        function refresh(): void { appearance.refreshLocation(); }
        function fixed(lat: real, lon: real): bool { return appearance.useFixedLocation(lat, lon); }
        function reset(): bool { return appearance.resetPreferences(); }
        function resume(): void { appearance.resumeAutomatic(); }
        function status(): string { return JSON.stringify({dark: appearance.darkMode,
            selected: appearance.selectedMode, preferencesOverridden: appearance.preferencesOverridden,
            settings: appearance.effectiveSettings, automatic: appearance.automatic, next: appearance.nextTransition,
            available: appearance.appearanceAvailable, location: appearance.locationStatus,
            until: appearance.overrideUntil, error: appearance.appearanceError, configError: config.error}); }
    }
}''')
    env = dict(os.environ, HOME=str(base), XDG_STATE_HOME=str(base / 'state'), XDG_CONFIG_HOME=str(base / 'config'),
        XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(base / 'cache'), QT_QPA_PLATFORM='offscreen',
        QT_QUICK_BACKEND='software', DBUS_SESSION_BUS_ADDRESS='unix:path=' + str(base / 'no-session'),
        DBUS_SYSTEM_BUS_ADDRESS='unix:path=' + str(base / 'no-system'), PATH=str(base) + os.pathsep + os.environ['PATH'],
        TZ='Test/Local', TZDIR=str(tzdata))
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
            wait(lambda s: s['available'] and s['location'] == 'inactive')
            assert ipc('select', 'auto').stdout.strip() == 'true'
            wait(lambda s: s['settings']['location'] == 'timezone' and s['location'] == 'ready'
                and s['automatic'] and s['next'] is not None and s['dark'] == first and not s['error'])
            set_zone(other_lon)
            ipc('refresh')
            wait(lambda s: s['dark'] != first and s['next'] is not None and not s['error'])
            assert not location_calls.exists(), 'Default Auto and timezone refresh must not query BeaconDB'
            child.terminate(); child.wait(timeout=5)
            child = start()
            wait(lambda s: s['location'] == 'ready' and s['automatic'] and s['next'] is not None)
            assert not location_calls.exists(), 'Restarting in timezone mode must not query BeaconDB'
            configure(mode='manual', lon=None)
            ipc('reset')
            wait(lambda s: s['settings']['location'] == 'fixed' and s['location'] == 'inactive')
            assert ipc('select', 'auto').stdout.strip() == 'true'
            wait(lambda s: s['settings']['location'] == 'timezone' and s['location'] == 'ready')
            assert not location_calls.exists(), 'Empty fixed settings from older releases must use offline Auto'
            ipc('reset')
            configure(location='geoclue', lon=None)
            wait(lambda s: not s['preferencesOverridden'] and s['settings']['location'] == 'timezone' and s['location'] == 'ready')
            assert not location_calls.exists(), 'A legacy GeoClue preference must not authorize BeaconDB'
            assert ipc('useIp').stdout.strip() == 'true'
            wait(lambda s: s['location'] == 'unavailable' and s['dark'] != first and 'IP location unavailable' in s['error'])
            assert len(location_calls.read_text().splitlines()) == 1
            location.write_text(json.dumps({'location': {'lat': 0, 'lng': longitude}, 'accuracy': 25000, 'fallback': 'ipf'}))
            ipc('reset')
            configure(mode='manual', location='ip', lon=None)
            wait(lambda s: s['settings']['location'] == 'ip' and s['location'] == 'inactive')
            assert len(location_calls.read_text().splitlines()) == 1
            assert ipc('select', 'auto').stdout.strip() == 'true'
            wait(lambda s: s['location'] == 'ready' and s['next'] is not None and s['dark'] == first and not s['error'])
            resolved = json.loads((state / 'appearance-policy.json').read_text())['appearance']
            assert resolved['latitude'] is None and resolved['longitude'] is None, 'IP coordinates must stay in memory'
            location.unlink()
            ipc('refresh')
            wait(lambda s: 'using the last estimate' in s['error'] and s['next'] is not None and s['dark'] == first)
            ipc('reset')
            configure()
            wait(lambda s: s['dark'] == first and s['next'] is not None and not s['error'])
            assert len(location_calls.read_text().splitlines()) == 3
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
            configure(location='ip')
            wait(lambda s: s['automatic'] and 'IP location unavailable' in s['error'] and s['dark'] == first)
            configure()
            wait(lambda s: not s['error'] and s['next'] is not None)
            # UI mode choices survive restart and never mutate config.json.
            before = config.read_bytes()
            ipc('select', 'light')
            wait(lambda s: s['selected'] == 'light' and s['preferencesOverridden'])
            child.terminate(); child.wait(timeout=5)
            child = start()
            wait(lambda s: s['selected'] == 'light' and s['preferencesOverridden'])
            ipc('select', 'auto')
            wait(lambda s: s['selected'] == 'auto' and s['next'] is not None)
            assert ipc('fixed', '91', '0').stdout.strip() == 'false'
            ipc('fixed', '0', str(other_lon))
            wait(lambda s: s['settings']['longitude'] == other_lon and s['dark'] != first)
            assert config.read_bytes() == before
            ipc('reset')
            wait(lambda s: not s['preferencesOverridden'] and s['dark'] == first)

        finally:
            child.terminate(); child.wait(timeout=5)
    text = log.read_text()
    assert not any(x in text for x in ('ReferenceError', 'TypeError', 'SyntaxError', 'Cannot assign')), text
print('Solar QML policy, offline timezone and refresh, opt-in BeaconDB, failure fallback, fixed coordinates and restart passed')

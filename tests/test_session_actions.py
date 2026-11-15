"""Session command routing with fake executables and no host bus access."""
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile

source = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix='ns-session-', dir='/tmp') as temporary:
    base = Path(temporary)
    shutil.copy2(source / 'session_actions.qml', base / 'shell.qml')
    shutil.copy2(source.parent / 'SessionActions.qml', base / 'SessionActions.qml')
    binaries = base / 'bin'
    binaries.mkdir()
    script = '''import json,os,pathlib,sys
name=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
if name == "busctl":
    method=args[-1]
    print(json.dumps({"type":"s","data":[{"CanReboot":"challenge","CanPowerOff":"no","CanSuspend":"yes"}[method]]}))
    sys.exit(0)
if name == "uwsm" and args == ["check","is-active"]:
    sys.exit(0 if os.environ["TEST_UWSM"] == "yes" else 1)
with open(os.environ["TEST_CALLS"],"a") as out: out.write(json.dumps([name]+args)+"\\n")
if args[-1] == "suspend":
    print("Synthetic denial",file=sys.stderr)
    sys.exit(1)
'''
    for name in ['busctl', 'systemctl', 'uwsm', 'loginctl']:
        tool = binaries / name
        tool.write_text('#!' + sys.executable + '\n' + script)
        tool.chmod(0o755)
    for uwsm in ['yes', 'no']:
        calls = base / ('calls-' + uwsm)
        env = dict(os.environ, PATH=str(binaries) + os.pathsep + os.environ['PATH'],
                   HOME=str(base), XDG_CONFIG_HOME=str(base / 'config'),
                   XDG_CACHE_HOME=str(base / 'cache'), XDG_RUNTIME_DIR=str(base),
                   XDG_SESSION_ID='synthetic-session', QT_QPA_PLATFORM='offscreen',
                   TEST_UWSM=uwsm, TEST_CALLS=str(calls),
                   DBUS_SYSTEM_BUS_ADDRESS='unix:path=' + str(base / 'no-system'),
                   DBUS_SESSION_BUS_ADDRESS='unix:path=' + str(base / 'no-session'))
        env.pop('WAYLAND_DISPLAY', None)
        result = subprocess.run(['quickshell', '--path', str(base / 'shell.qml')],
                                env=env, text=True, capture_output=True, timeout=12)
        assert result.returncode == 0 and 'SESSION_ACTIONS_OK' in result.stdout + result.stderr, result.stdout + result.stderr
        actual = [json.loads(line) for line in calls.read_text().splitlines()]
        logout = ['uwsm', 'stop'] if uwsm == 'yes' else ['loginctl', 'terminate-session', 'synthetic-session']
        assert actual == [['systemctl', '--no-ask-password', '--no-block', 'reboot'], logout,
                          ['systemctl', '--no-ask-password', '--no-block', 'suspend']], actual
print('Session actions: capability gating, command argv, UWSM/logind logout and failure feedback passed')

#!/usr/bin/env python3
"""Exercise the QML blur adapter using synthetic hyprctl replies, no compositor changes."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    quickshell = shutil.which('quickshell')
    if not quickshell:
        raise SystemExit('quickshell is required')
    source = Path(__file__).resolve().parents[1]
    cases = [
        ('unsupported', None, False),
        ('enabled', 'printf \'%s\\n\' \'{"option":"decoration:blur:enabled","bool":true}\'', True),
        ('disabled', 'printf \'%s\\n\' \'{"option":"decoration:blur:enabled","bool":false}\'', False),
        ('malformed', 'echo invalid', False),
        ('failed', 'echo \'{"option":"decoration:blur:enabled","bool":true}\'; exit 1', False),
        ('timeout', 'exec sleep 10', False),
    ]
    with tempfile.TemporaryDirectory(prefix='ns-material-', dir='/tmp') as temporary:
        root = Path(temporary)
        for name, command, expected in cases:
            case = root / name
            case.mkdir()
            runtime = case / 'runtime'
            runtime.mkdir(mode=0o700)
            executable = case / 'hyprctl'
            executable.write_text('#!/bin/sh\n' + (command or 'exit 99') + '\n')
            executable.chmod(0o755)
            entry = case / 'shell.qml'
            entry.write_text('''import QtQuick
import Quickshell
import %s as App
ShellRoot {
    App.SurfaceCapabilities { id: capability }
    Timer {
        interval: 1900
        running: true
        onTriggered: {
            console.log("CAPABILITY", capability.blurAvailable);
            Qt.quit();
        }
    }
}
''' % json.dumps(source.as_uri()))
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       XDG_RUNTIME_DIR=str(runtime), PATH=str(case) + os.pathsep + os.environ['PATH'])
            env.pop('WAYLAND_DISPLAY', None)
            if command is None:
                env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
            else:
                env['HYPRLAND_INSTANCE_SIGNATURE'] = 'synthetic-material-test'
            result = subprocess.run([quickshell, '-p', str(entry)], env=env,
                                    capture_output=True, text=True, timeout=6)
            log = result.stdout + result.stderr
            assert result.returncode == 0 and 'CAPABILITY ' + str(expected).lower() in log, (name, log)
            print(name, 'passed')


if __name__ == '__main__':
    main()

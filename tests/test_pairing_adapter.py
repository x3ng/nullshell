#!/usr/bin/env python3
"""Exercise the production QML pairing adapter with a synthetic stdio peer.

Only the executable path is replaced in a temporary copy, so packaged PATH
wrappers cannot accidentally launch the real helper. No D-Bus or radio access.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

HELPER = r'''
import json, os, sys, time
case = os.environ['PAIRING_TEST_CASE']
assert sys.argv[1:] == ['bluetooth-agent', 'AA:BB:CC:DD:EE:FF', 'hci-test']
def emit(**event):
    print(json.dumps(dict(version=1, **event)), flush=True)
if case == 'crash':
    sys.exit(1)
if case == 'failure':
    emit(type='done', success=False, error='Synthetic failure')
    sys.exit()
print('not-json', flush=True)
print('null', flush=True)
print('{"version":2,"type":"done","success":true}', flush=True)
emit(type='done', success='invalid')
emit(type='prompt', kind='unknown', code='', id=0)
emit(type='prompt', kind='confirm', code='123456', id=7)
time.sleep(.15)
if case in ('cancel', 'stuck'):
    assert json.loads(sys.stdin.readline()) == {'version': 1, 'cancel': True}
    if case == 'stuck': time.sleep(20)
    emit(type='done', success=True)  # Late success must not trigger policy.
else:
    emit(type='cancelled')
    time.sleep(.15)
    emit(type='prompt', kind='passkey', code='', id=8)
    assert json.loads(sys.stdin.readline()) == {'version': 1, 'id': 8, 'answer': '123456'}
    emit(type='done', success=True)
'''

QML = r'''
import QtQuick
import Quickshell
ShellRoot {
    id: test
    property string scenario: Quickshell.env("PAIRING_TEST_CASE")
    property var selected: fakeDevice
    QtObject {
        id: fakeDevice
        property string address: "AA:BB:CC:DD:EE:FF"
        property QtObject adapter: QtObject { property string adapterId: "hci-test" }
    }
    property int phase: 0
    property int completions: 0
    function check(value, message) {
        if (!value) { console.error("ASSERTION", message); Qt.quit(); }
        return value;
    }
    BluetoothPairing {
        id: pairing
        onPromptChanged: Qt.callLater(() => {
            if (prompt === "confirm") {
                test.phase = 1;
                if (test.scenario === "cancel" || test.scenario === "stuck") {
                    test.check(cancel(), "cancel accepted");
                    test.check(device === null && prompt === "" && code === "", "cancel clears state");
                    test.check(!start(test.selected), "no overlap during cleanup");
                }
            } else if (prompt === "" && test.phase === 1 && test.scenario === "success") {
                test.check(device === test.selected, "prompt cancellation keeps operation");
                test.check(!answer("yes"), "cancelled prompt cannot be answered");
                test.phase = 2;
            } else if (prompt === "passkey") {
                test.check(test.phase === 2, "observed cancellation before new prompt");
                test.check(!answer("invalid"), "reject invalid passkey");
                test.check(answer("123456"), "answer current request");
                test.phase = 3;
            }
        })
        onFinished: (completedDevice, success, error) => {
            test.completions++;
            test.check(completedDevice === test.selected && device === null && prompt === "" && code === "", "terminal state cleared");
            if (test.scenario === "success") test.check(success && test.phase === 3, "success after answer");
            else test.check(!success && error.length > 0, "failure feedback");
        }
    }
    Component.onCompleted: {
        check(pairing.start(selected), "start accepted");
        check(!pairing.start(selected), "duplicate rejected");
    }
    Timer {
        interval: 50; running: true; repeat: true
        onTriggered: {
            if (pairing.busy) return;
            const cancelled = test.scenario === "cancel" || test.scenario === "stuck";
            if (!test.check(test.completions === (cancelled ? 0 : 1), "exactly one result, none after cancellation")) return;
            console.log("PAIRING_ADAPTER_PASS", test.scenario);
            Qt.quit();
        }
    }
    Timer { interval: 9000; running: true; onTriggered: { console.error("ASSERTION timeout"); Qt.quit(); } }
}
'''


def main():
    source = Path(__file__).resolve().parents[1] / 'adapters/BluetoothPairing.qml'
    with tempfile.TemporaryDirectory(prefix='nullshell-pairing-', dir='/tmp') as temporary:
        root = Path(temporary)
        runtime = root / 'runtime'
        runtime.mkdir(mode=0o700)
        helper = root / 'helper'
        helper.write_text('#!' + sys.executable + '\n' + HELPER)
        helper.chmod(0o755)
        (root / 'shell.qml').write_text(QML)
        for case in ['success', 'failure', 'crash', 'cancel', 'stuck', 'missing']:
            executable = root / 'missing' if case == 'missing' else helper
            (root / 'BluetoothPairing.qml').write_text(source.read_text().replace('"nullshell-helper"', json.dumps(str(executable))))
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       XDG_RUNTIME_DIR=str(runtime), PAIRING_TEST_CASE=case,
                       DBUS_SYSTEM_BUS_ADDRESS='unix:path=' + str(root / 'no-system-bus'))
            env.pop('WAYLAND_DISPLAY', None)
            result = subprocess.run(['quickshell', '-p', str(root / 'shell.qml')], env=env,
                                    capture_output=True, text=True, timeout=12)
            log = result.stdout + result.stderr
            assert result.returncode == 0 and 'PAIRING_ADAPTER_PASS ' + case in log and not any(error in log for error in ['ASSERTION', 'TypeError', 'ReferenceError', 'Binding loop']), (case, log)
            print(case, 'passed')


if __name__ == '__main__':
    main()

"""Synthetic logind and commands on a private bus; never lock/suspend the host."""
import asyncio
import json
import logging
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from dbus_next import PropertyAccess, DBusError
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method, signal, dbus_property

LOGIN = 'org.freedesktop.login1'
MANAGER = '/org/freedesktop/login1'
SESSION = MANAGER + '/session/test'


class Session(ServiceInterface):
    def __init__(self):
        super().__init__(LOGIN + '.Session')

    @signal()
    def Lock(self):
        pass


class Manager(ServiceInterface):
    def __init__(self):
        super().__init__(LOGIN + '.Manager')
        self.preparing = False
        self.pipes = []
        self.deny = False

    @method()
    def GetSession(self, session: 's') -> 'o':
        assert session == 'synthetic'
        return SESSION

    @method()
    def GetSessionByPID(self, pid: 'u') -> 'o':
        assert pid > 0
        return SESSION

    @method()
    def Inhibit(self, what: 's', who: 's', why: 's', mode: 's') -> 'h':
        assert (what, who, mode) == ('sleep', 'nullshell', 'delay')
        if self.deny:
            raise DBusError('org.freedesktop.DBus.Error.AccessDenied', 'Synthetic denial')
        reader, writer = os.pipe2(os.O_NONBLOCK | os.O_CLOEXEC)
        self.pipes.append(reader)
        # dbus-next transfers a duplicate; close the mock's copy after sending.
        asyncio.get_running_loop().call_later(.05, os.close, writer)
        return writer

    @dbus_property(access=PropertyAccess.READ)
    def PreparingForSleep(self) -> 'b':
        return self.preparing

    @signal()
    def PrepareForSleep(self, preparing: 'b') -> 'b':
        self.preparing = preparing
        return preparing

    @signal()
    def SessionRemoved(self, name: 's', path: 'o') -> 'so':
        return [name, path]


def closed(fd):
    try:
        return os.read(fd, 1) == b''
    except BlockingIOError:
        return False


async def eventually(check, timeout=3):
    async with asyncio.timeout(timeout):
        while not check():
            await asyncio.sleep(.02)


async def main(helper, base):
    # dbus-next logs our intentional AccessDenied reply as an exception.
    logging.getLogger().setLevel(logging.CRITICAL)
    os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = os.environ['DBUS_SESSION_BUS_ADDRESS']
    os.environ['XDG_SESSION_ID'] = 'synthetic'
    os.environ['XDG_RUNTIME_DIR'] = str(base)
    bus = await MessageBus(negotiate_unix_fd=True).connect()
    manager, session, other = Manager(), Session(), Session()
    bus.export(MANAGER, manager)
    bus.export(SESSION, session)
    bus.export(MANAGER + '/session/other', other)
    await bus.request_name(LOGIN)
    fake = base / 'command.py'
    fake.write_text('''import pathlib,sys,time,subprocess
base=pathlib.Path(sys.argv[1]); mode=sys.argv[2]
with (base/(mode+".calls")).open("a") as f: f.write("called\\n")
if mode == "lock":
    if (base/"spawn-child").exists():
        child=subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"])
        (base/"child.pid").write_text(str(child.pid))
    while not (base/"answer").exists(): time.sleep(.02)
    sys.exit(int((base/"answer").read_text()))
''')
    def argv(mode):
        return json.dumps([sys.executable, str(fake), str(base), mode])
    args = [helper, 'sleep-bridge', '--lock-command', argv('lock'), '--resume-command', argv('resume')]
    children = []
    async def start():
        process = await asyncio.create_subprocess_exec(*args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        children.append(process)
        return process
    async def event(process, name, timeout=4):
        async with asyncio.timeout(timeout):
            while True:
                line = await process.stdout.readline()
                assert line, (await process.stderr.read()).decode()
                value = json.loads(line)
                assert value['version'] == 1
                if value['event'] == name:
                    return
    def calls(mode):
        path = base / (mode + '.calls')
        return len(path.read_text().splitlines()) if path.exists() else 0
    answer = base / 'answer'
    try:
        process = await start()
        await event(process, 'ready')
        await asyncio.sleep(.1)
        first = manager.pipes[-1]
        assert not closed(first)
        duplicate = await start()
        assert await asyncio.wait_for(duplicate.wait(), 4) != 0
        other.Lock()
        rogue = await MessageBus().connect()
        rogue_session = Session()
        rogue.export(SESSION, rogue_session)
        rogue_session.Lock()
        manager.SessionRemoved('other', MANAGER + '/session/other')
        await asyncio.sleep(.15)
        assert calls('lock') == 0 and process.returncode is None
        rogue.disconnect()

        # External lock confirms but does not release the next-sleep inhibitor.
        answer.write_text('0')
        session.Lock()
        await event(process, 'locked')
        assert not closed(first)
        answer.unlink()
        manager.PrepareForSleep(True)
        await eventually(lambda: calls('lock') == 2)
        await asyncio.sleep(.1)
        assert not closed(first), 'Inhibitor released before locker confirmation'
        answer.write_text('0')
        await event(process, 'sleep-released')
        await eventually(lambda: closed(first))
        manager.PrepareForSleep(False)
        await event(process, 'resumed')
        await eventually(lambda: calls('resume') == 1)
        second = manager.pipes[-1]
        assert second != first and not closed(second)

        # Nonzero exit never acknowledges security or releases the FD.
        answer.write_text('1')
        manager.PrepareForSleep(True)
        await event(process, 'lock-failed')
        assert not closed(second)
        manager.PrepareForSleep(False)
        await event(process, 'resumed')
        assert manager.pipes[-1] == second

        # Timeout is bounded and also keeps the inhibitor; command is reaped.
        answer.unlink()
        manager.PrepareForSleep(True)
        await event(process, 'lock-failed', timeout=15)
        assert not closed(second)
        manager.PrepareForSleep(False)
        await event(process, 'resumed')

        # Resume and a new sleep while an earlier lock is pending: stale success
        # must trigger a fresh lock, never acknowledge the new cycle directly.
        before = calls('lock')
        manager.PrepareForSleep(True)
        await event(process, 'locking')
        await eventually(lambda: calls('lock') > before)
        manager.PrepareForSleep(False)
        await event(process, 'resumed')
        manager.PrepareForSleep(True)
        await event(process, 'preparing')
        before = calls('lock')
        answer.write_text('0')
        await event(process, 'sleep-released')
        assert calls('lock') == before + 1
        manager.PrepareForSleep(False)
        await event(process, 'resumed')
        third = manager.pipes[-1]
        manager.SessionRemoved('synthetic', SESSION)
        assert await asyncio.wait_for(process.wait(), 4) == 0
        await eventually(lambda: closed(third))

        # Attach during an existing sleep preparation and handle service loss.
        manager.preparing = True
        answer.unlink()
        (base / 'spawn-child').touch()
        process = await start()
        await event(process, 'ready')
        await eventually(lambda: (base / 'child.pid').exists())
        child_pid = int((base / 'child.pid').read_text())
        held = manager.pipes[-1]
        assert not closed(held)
        await bus.release_name(LOGIN)
        assert await asyncio.wait_for(process.wait(), 4) != 0
        await eventually(lambda: closed(held))
        def child_stopped():
            stat = Path(f'/proc/{child_pid}/stat')
            return not stat.exists() or stat.read_text().split(')')[1].split()[0] == 'Z'
        await eventually(child_stopped)
        (base / 'spawn-child').unlink()
        await bus.request_name(LOGIN)
        manager.preparing = False
        process = await start()
        await event(process, 'ready')
        held = manager.pipes[-1]
        process.terminate()
        assert await asyncio.wait_for(process.wait(), 4) == 0
        await eventually(lambda: closed(held))

        # Failed acquisition cannot announce readiness; missing commands cannot
        # release an acquired inhibitor. Abrupt process death closes the FD too.
        manager.deny = True
        process = await start()
        assert await asyncio.wait_for(process.wait(), 4) != 0
        assert await process.stdout.read() == b''
        manager.deny = False
        os.environ.pop('XDG_SESSION_ID')  # Exercise PID-based session discovery.
        args[3] = json.dumps([str(base / 'missing-lock-command')])
        process = await start()
        await event(process, 'ready')
        held = manager.pipes[-1]
        manager.PrepareForSleep(True)
        await event(process, 'lock-failed')
        assert not closed(held)
        process.kill()
        await process.wait()
        await eventually(lambda: closed(held))
        print('Sleep bridge: real FD lifetime, lock/timeout, resume, stale replies, duplicates, session and owner loss passed')
    finally:
        for child in children:
            if child.returncode is None:
                child.kill()
            await child.wait()
        for fd in manager.pipes:
            os.close(fd)
        bus.disconnect()


if __name__ == '__main__':
    if '--private-bus' not in sys.argv:
        with tempfile.TemporaryDirectory(prefix='nullshell-sleep-bus-') as tmp:
            config = Path(tmp) / 'bus.conf'
            config.write_text('''<busconfig>
<type>session</type><listen>unix:tmpdir=/tmp</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*"/>
<allow receive_sender="*"/><allow own="*"/></policy>
</busconfig>''')
            subprocess.run(['dbus-run-session', '--config-file=' + str(config), '--',
                            sys.executable, __file__, sys.argv[1], '--private-bus'], check=True)
    else:
        with tempfile.TemporaryDirectory(prefix='nullshell-sleep-test-') as tmp:
            asyncio.run(main(str(Path(sys.argv[1]).resolve()), Path(tmp)))

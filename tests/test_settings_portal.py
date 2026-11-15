"""Protocol tests on a fresh session bus, also used as a synthetic system bus."""
import asyncio
import json
import logging
from html import escape
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from dbus_next import Message, MessageType, MessageFlag, DBusError, PropertyAccess
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method, dbus_property

NAME = 'org.freedesktop.impl.portal.desktop.nullshell'
PATH = '/org/freedesktop/portal/desktop'
IFACE = 'org.freedesktop.impl.portal.Settings'
NS = 'org.freedesktop.appearance'
GEO = '/org/freedesktop/GeoClue2'

class Manager(ServiceInterface):
    def __init__(self):
        super().__init__('org.freedesktop.GeoClue2.Manager')
        self.deleted = 0
    @method()
    def GetClient(self) -> 'o':
        return GEO + '/Client/1'
    @method()
    def DeleteClient(self, path: 'o'):
        assert path == GEO + '/Client/1'
        self.deleted += 1

class Client(ServiceInterface):
    def __init__(self):
        super().__init__('org.freedesktop.GeoClue2.Client')
        self.desktop = ''
        self.accuracy = 0
        self.deny = False
        self.started = False
        self.hang = False
    @dbus_property(access=PropertyAccess.READWRITE)
    def DesktopId(self) -> 's': return self.desktop
    @DesktopId.setter
    def DesktopId(self, value: 's'): self.desktop = value
    @dbus_property(access=PropertyAccess.READWRITE)
    def RequestedAccuracyLevel(self) -> 'u': return self.accuracy
    @RequestedAccuracyLevel.setter
    def RequestedAccuracyLevel(self, value: 'u'): self.accuracy = value
    @dbus_property(access=PropertyAccess.READ)
    def Location(self) -> 'o': return GEO + '/Location/1' if self.started else '/'
    @method()
    def Start(self):
        if self.deny: raise DBusError('org.freedesktop.DBus.Error.AccessDenied', 'Synthetic denial')
        assert self.desktop == 'org.nullshell.desktop' and self.accuracy == 4
        self.started = not self.hang

class Location(ServiceInterface):
    def __init__(self):
        super().__init__('org.freedesktop.GeoClue2.Location')
        self.latitude = 12.3456
    @dbus_property(access=PropertyAccess.READ)
    def Latitude(self) -> 'd': return self.latitude
    @dbus_property(access=PropertyAccess.READ)
    def Longitude(self) -> 'd': return -67.8912

async def main(helper, base):
    # dbus-next logs deliberate mock D-Bus errors as exceptions; assertions below
    # verify their actual wire replies and cleanup.
    logging.getLogger().setLevel(logging.CRITICAL)
    bus = await MessageBus().connect()
    state = base / 'state/nullshell/appearance-mode'
    state.parent.mkdir(parents=True)
    process = await asyncio.create_subprocess_exec(helper, 'settings-portal', stderr=asyncio.subprocess.PIPE)
    def write(text):
        temp = state.with_suffix('.tmp')
        temp.write_text(text)
        temp.replace(state)
    async def call(member, signature='', body=[]):
        return await bus.call(Message(destination=NAME, path=PATH, interface=IFACE, member=member, flags=MessageFlag.NO_AUTOSTART,
                                      signature=signature, body=body))
    async def read(): return await call('Read', 'ss', [NS, 'color-scheme'])
    async def wait_value(value):
        for _ in range(60):
            reply = await read()
            if reply.message_type == MessageType.METHOD_RETURN and reply.body[0].value == value:
                assert reply.signature == 'v' and reply.body[0].signature == 'u'
                return
            await asyncio.sleep(.05)
        raise AssertionError(reply)
    try:
        await wait_value(0)
        introspection = await bus.introspect(NAME, PATH)
        proxy = bus.get_proxy_object(NAME, PATH, introspection).get_interface(IFACE)
        events = []
        proxy.on_setting_changed(lambda namespace, key, value: events.append((namespace, key, value.value)))
        assert await proxy.get_version() == 1
        for filters in ([], [''], ['org.freedesktop.*'], [NS]):
            result = await proxy.call_read_all(filters)
            assert result[NS]['color-scheme'].value == 0
        assert await proxy.call_read_all(['org.gnome.*']) == {}
        unknown = await call('Read', 'ss', [NS, 'unknown'])
        assert unknown.error_name == 'org.freedesktop.portal.Error.NotFound'
        for text, value in [('dark\n', 1), ('light\n', 2)]:
            write(text)
            await wait_value(value)
        assert events == [(NS, 'color-scheme', 1), (NS, 'color-scheme', 2)]
        write('corrupt')
        await asyncio.sleep(1.1)
        await wait_value(2)
        state.unlink()
        await asyncio.sleep(1.1)
        await wait_value(2)
        assert len(events) == 2
        duplicate = await asyncio.create_subprocess_exec(helper, 'settings-portal', stderr=asyncio.subprocess.PIPE)
        assert await asyncio.wait_for(duplicate.wait(), 5) != 0
        await wait_value(2)
        write('dark\n')
    finally:
        process.terminate()
        await process.wait()
    process = await asyncio.create_subprocess_exec(helper, 'settings-portal')
    try:
        await wait_value(1)  # late-started backend loads the desktop snapshot
    finally:
        process.terminate()
        await process.wait()

    manager, client = Manager(), Client()
    bus.export(GEO + '/Manager', manager)
    bus.export(GEO + '/Client/1', client)
    location = Location()
    bus.export(GEO + '/Location/1', location)
    await bus.request_name('org.freedesktop.GeoClue2')
    for action in ('success', 'denied', 'invalid', 'timeout'):
        client.deny = action == 'denied'
        client.hang = action == 'timeout'
        location.latitude = float('nan') if action == 'invalid' else 12.3456
        child = await asyncio.create_subprocess_exec(helper, 'location', stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        out, err = await asyncio.wait_for(child.communicate(), 25)
        if action != 'success':
            assert child.returncode != 0 and not out
            assert b'12.3456' not in err
        else:
            assert child.returncode == 0 and not err
            assert json.loads(out) == {'version': 1, 'latitude': 12.3, 'longitude': -67.9}
    assert manager.deleted == 4
    if os.environ.get('NULLSHELL_TEST_PORTAL'):
        frontend = await asyncio.create_subprocess_exec(os.environ['NULLSHELL_TEST_PORTAL'],
            stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE)
        try:
            async def frontend_read():
                return await bus.call(Message(destination='org.freedesktop.portal.Desktop', path=PATH,
                    interface='org.freedesktop.portal.Settings', member='ReadOne', signature='ss', flags=MessageFlag.NO_AUTOSTART,
                    body=[NS, 'color-scheme']))
            for _ in range(100):
                reply = await frontend_read()
                if reply.message_type == MessageType.METHOD_RETURN:
                    break
                await asyncio.sleep(.1)
            assert reply.message_type == MessageType.METHOD_RETURN, reply
            assert reply.body[0].value == 1, reply.body
            # The real frontend discovers our descriptor and D-Bus activates the backend.
            # Raw messages avoid dbus-next's stricter-than-D-Bus property-name
            # parser on unrelated frontend interfaces (e.g. power-saver-enabled).
            forwarded = []
            def changed(message):
                if message.message_type == MessageType.SIGNAL and message.interface == 'org.freedesktop.portal.Settings' and message.member == 'SettingChanged':
                    ns, key, value = message.body
                    forwarded.append((ns, key, value.value))
            bus.add_message_handler(changed)
            await bus.call(Message(destination='org.freedesktop.DBus', path='/org/freedesktop/DBus',
                interface='org.freedesktop.DBus', member='AddMatch', signature='s',
                body=["type='signal',interface='org.freedesktop.portal.Settings',member='SettingChanged',sender='org.freedesktop.portal.Desktop'"]))
            write('light\n')
            for _ in range(60):
                if forwarded: break
                await asyncio.sleep(.05)
            assert forwarded == [(NS, 'color-scheme', 2)], forwarded
            result = await bus.call(Message(destination='org.freedesktop.portal.Desktop', path=PATH,
                interface='org.freedesktop.portal.Settings', member='ReadAll', signature='as', body=[[NS]]))
            assert result.body[0][NS]['color-scheme'].value == 2
            print('Real xdg-desktop-portal discovery, D-Bus activation, ReadOne/ReadAll and forwarded signals passed')
        finally:
            frontend.terminate()
            await frontend.wait()
    bus.disconnect()
    print('Settings Read/ReadAll/signals/recovery/name ownership and GeoClue coarse request/denial/invalid data/timeout/cleanup passed')

if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[2] == '--private':
        os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = os.environ['DBUS_SESSION_BUS_ADDRESS']
        asyncio.run(main(sys.argv[1], Path(os.environ['HOME'])))
    else:
        with tempfile.TemporaryDirectory(prefix='nullshell-settings-') as directory:
            env = dict(os.environ, HOME=directory, XDG_STATE_HOME=directory + '/state',
                       XDG_CONFIG_HOME=directory + '/config', XDG_DATA_HOME=directory + '/data')
            if env.get('NULLSHELL_TEST_PORTAL'):
                data = Path(directory) / 'data'
                services = data / 'dbus-1/services'; services.mkdir(parents=True)
                integration = Path(__file__).resolve().parent.parent / 'integration'
                template = (integration / (NAME + '.service.in')).read_text()
                (services / (NAME + '.service')).write_text(template.replace('@HELPER@', str(Path(sys.argv[1]).resolve())))
                portals = data / 'xdg-desktop-portal/portals'; portals.mkdir(parents=True)
                (portals / 'nullshell.portal').write_text((integration / 'nullshell.portal').read_text())
                config = Path(directory) / 'config/xdg-desktop-portal'; config.mkdir(parents=True)
                (config / 'portals.conf').write_text('[preferred]\ndefault=nullshell;\norg.freedesktop.impl.portal.Settings=nullshell;\n')
                runtime = Path(directory) / 'runtime'; runtime.mkdir(mode=0o700)
                env.update(XDG_CURRENT_DESKTOP='nullshell', XDG_DESKTOP_PORTAL_DIR=str(portals),
                    XDG_RUNTIME_DIR=str(runtime), DBUS_SYSTEM_BUS_ADDRESS='unix:path=' + directory + '/no-system')
            # Explicit service directory: never discover host activation services.
            bus_config = Path(directory) / 'bus.conf'
            services = Path(directory) / 'data/dbus-1/services'
            services.mkdir(parents=True, exist_ok=True)
            bus_config.write_text('<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>'
                '<auth>EXTERNAL</auth><servicedir>' + escape(str(services)) + '</servicedir>'
                '<policy context="default"><allow send_destination="*"/><allow receive_sender="*"/>'
                '<allow own="*"/></policy></busconfig>')
            subprocess.run(['dbus-run-session', '--config-file=' + str(bus_config), '--', sys.executable, __file__, str(Path(sys.argv[1]).resolve()), '--private'], env=env, check=True, timeout=70)

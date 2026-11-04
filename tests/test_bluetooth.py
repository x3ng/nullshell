"""Private-bus BlueZ integration tests; no host radio or pairing is used."""
import asyncio
import json
import sys
from dbus_next import Message, MessageType, DBusError
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method

DEVICE = '/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF'


class Manager(ServiceInterface):
    def __init__(self):
        super().__init__('org.bluez.AgentManager1')
        self.sender = None
        self.path = None
        self.registrations = 0
        self.unregistrations = 0

    @method()
    def RegisterAgent(self, path: 'o', capability: 's'):
        assert capability == 'KeyboardDisplay'
        self.path = path
        self.registrations += 1

    @method()
    def UnregisterAgent(self, path: 'o'):
        assert path == self.path
        self.unregistrations += 1


class Device(ServiceInterface):
    def __init__(self, bus, manager):
        super().__init__('org.bluez.Device1')
        self.bus = bus
        self.manager = manager
        self.cancelled = 0
        self.prompt = 'RequestConfirmation'

    @method()
    async def Pair(self):
        signature, body = ('ou', [DEVICE, 123456]) if self.prompt == 'RequestConfirmation' else ('o', [DEVICE])
        response = await self.bus.call(Message(destination=self.manager.sender, path=self.manager.path,
                                             interface='org.bluez.Agent1', member=self.prompt,
                                             signature=signature, body=body))
        if response.message_type == MessageType.ERROR:
            raise DBusError('org.bluez.Error.AuthenticationRejected', 'Rejected')

    @method()
    def CancelPairing(self):
        self.cancelled += 1


async def scenario(helper, manager, device, action, success, prompt='RequestConfirmation'):
    device.prompt = prompt
    before = manager.unregistrations
    process = await asyncio.create_subprocess_exec(
        helper, 'bluetooth-agent', 'AA:BB:CC:DD:EE:FF', 'hci0', '--session-bus',
        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    try:
        async def event():
            line = await asyncio.wait_for(process.stdout.readline(), timeout=5)
            assert line, 'Helper exited without a terminal event'
            return json.loads(line)
        assert (await event())['type'] == 'ready'
        request = await event()
        assert request['type'] == 'prompt' and request['version'] == 1
        stranger = await MessageBus().connect()
        try:
            denied = await stranger.call(Message(destination=manager.sender, path=manager.path,
                                                interface='org.bluez.Agent1', member='RequestConfirmation',
                                                signature='ou', body=[DEVICE, 123456]))
            assert denied.message_type == MessageType.ERROR
        finally:
            stranger.disconnect()
        if action == 'owner-loss':
            device.bus.disconnect()
        elif action == 'eof':
            process.stdin.close()
        elif action == 'oversize':
            process.stdin.write(b'x' * 4097 + b'\n')
            await process.stdin.drain()
        else:
            # A stale reply must not satisfy the current prompt.
            process.stdin.write((json.dumps({'version': 1, 'id': request['id'] + 1, 'answer': 'yes'}) + '\n').encode())
            await process.stdin.drain()
            try:
                unexpected = await asyncio.wait_for(process.stdout.readline(), timeout=0.15)
                raise AssertionError(f'Stale reply advanced the protocol: {unexpected}')
            except asyncio.TimeoutError:
                pass
            reply = {'version': 1, 'cancel': True} if action == 'cancel' else {'version': 1, 'id': request['id'], 'answer': action}
            process.stdin.write((json.dumps(reply) + '\n').encode())
            await process.stdin.drain()
        result = await event()
        while result['type'] != 'done':
            result = await event()
        assert result['success'] is success, result
        assert await asyncio.wait_for(process.wait(), timeout=5) == 0
        if action != "owner-loss":
            assert manager.unregistrations == before + 1
        assert not (await process.stderr.read()), 'Sensitive answers must never reach stderr'
    finally:
        if process.returncode is None:
            process.kill()
            await process.wait()


async def main():
    bus = await MessageBus().connect()
    manager = Manager()
    device = Device(bus, manager)
    def sender(message):
        if message.message_type == MessageType.METHOD_CALL and message.member == 'RegisterAgent':
            manager.sender = message.sender
    bus.add_message_handler(sender)
    bus.export('/org/bluez', manager)
    bus.export(DEVICE, device)
    await bus.request_name('org.bluez')
    for action, success in [('yes', True), ('no', False), ('cancel', False), ('eof', False), ('oversize', False)]:
        await scenario(sys.argv[1], manager, device, action, success)
    await scenario(sys.argv[1], manager, device, '001234', True, 'RequestPasskey')
    await scenario(sys.argv[1], manager, device, '1234', True, 'RequestPinCode')
    assert device.cancelled == 4
    assert manager.registrations == manager.unregistrations == 7
    await scenario(sys.argv[1], manager, device, 'owner-loss', False)
    print('BlueZ private-bus confirmation, rejection, cancellation, EOF, bounds, PIN and passkey passed')


asyncio.run(main())

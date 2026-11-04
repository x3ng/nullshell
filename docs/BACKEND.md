# Rust helper protocol v1

`nullshell-helper bluetooth-agent AA:BB:CC:DD:EE:FF hci0` is a short-lived client
of the real BlueZ system D-Bus service. `--session-bus` is an explicit test option
for private-bus fixtures, not an environment-driven production override.

The helper exports Agent1 and registers KeyboardDisplay for its own Pair request.
It never requests the default-agent role. It checks that callbacks originate from
the captured unique BlueZ owner and refer to the selected device. Audio, device
lists, connection state and trust policy remain in Quickshell adapters.

All messages are JSON Lines. stdout contains only protocol events; diagnostic
stderr must not contain credentials. Each event has `version:1` and a `type`:

- `ready`: agent registered; Pair request is starting.
- `prompt`: `kind`, `code`, `id`. Interactive kinds are confirm, authorize, pin and
  passkey; display is informational with id 0. Display passkeys include entered.
- `cancelled`: clear any pending prompt (also emitted while finishing).
- `done`: terminal `success` boolean and a generic error message on failure.

Answers are `{"version":1,"id":N,"answer":"..."}`. A stale ID cannot answer
another prompt. Cancellation is `{"version":1,"cancel":true}`. Wrong answer
formats are ignored; unknown keys, invalid JSON/version, EOF or a line exceeding
4096 bytes cancel the operation. Prompt wait is bounded to 60 seconds and pairing
to 90 seconds. Cancellation cleanup calls have two-second bounds. Losing the
BlueZ unique owner terminates pairing; it must not attach to a replacement daemon.
No arbitrary command invocation, paths, remote requests or persistent credentials
are accepted by this protocol.

The helper unregisters when done and requests CancelPairing on failure. A killed
process loses its D-Bus connection; BlueZ owns cleanup of that vanished agent.
The desktop trusts/connects the device only after a successful requested pairing.

Build with `make helper` or Cargo directly. Use `cargo test --locked` for input
validation and `tests/test_bluetooth.py HELPER` under a private `dbus-run-session`
for mock BlueZ integration. The latter needs Python's dbus-next only as a test
dependency. Neither test touches a physical adapter.

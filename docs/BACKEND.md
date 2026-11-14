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

## QML ownership and call path

`components/ConnectivityPane.qml` calls `SystemControls` methods and reads its
pairing properties. It does not start processes or parse protocol messages.
`SystemControls.qml` owns native device state, eligibility checks, discovery,
connection feedback and the trust/connect policy after successful pairing.
`adapters/BluetoothPairing.qml` owns the short-lived process, JSON Lines,
prompt IDs, validation, startup failure, deadlines and cancellation. Its
`start()`/`answer()`/`cancel()` methods report acceptance; `finished()` reports
the terminal result. Pairing properties exposed to the page are read-only.

A `cancelled` event clears only the prompt, not the operation. Local cancellation
clears the UI immediately, ignores late results and waits for helper cleanup
before another process may start. A six-second fallback stops a stuck helper;
the helper itself owns BlueZ CancelPairing and UnregisterAgent. Switching away
from the connectivity page or closing the panel continues to cancel pairing.
Device removal and disabling Bluetooth also cancel the request.

This adapter is QML-side protocol glue, not an expansion of the Rust backend.
Native networking, audio, power and ordinary Bluetooth operations remain in
Quickshell. Existing service files can be split when needed; there is no generic
helper RPC layer or requirement to wrap every native property.

Run `make check-pairing` for offscreen QML tests with a synthetic stdio helper
(success, prompt cancellation, failure, crash, missing executable and stuck
cancellation). These tests neither use BlueZ nor replace real-radio integration.

## Appearance export

`nullshell-helper appearance-export SHARED_FILE` is an independent,
unprivileged one-shot subcommand, not part of the Bluetooth JSONL conversation.
It reads one appearance v1 JSON document (at most 16 KiB) until stdin EOF, validates
it, and atomically writes the shared target with mode 0640, inheriting the
installed directory's setgid group.
Failures go to stderr with nonzero exit status. User-session state remains
independent and is not rewritten by this command. No service or
D-Bus connection is started. See CONFIGURATION.md for the installation contract.

## Wallpaper export

`nullshell-helper wallpaper-export SHARED_FILE` reads a separate v1 request
(maximum 8 KiB) containing `source` and `fit`. It copies at most 16 MiB of raster
image data, atomically publishes a relative-resource descriptor, and retains only
two fixed image slots plus one fixed pending file. It never changes the appearance
snapshot. Fit-only updates preserve image bytes/revision; source-file change
notifications cause a fresh byte comparison. An empty source publishes no image
then removes managed assets. See CONFIGURATION.md for exact failure and cleanup
semantics. File locking requires Rust 1.89 or newer.


## Policy versus mechanism

QML/JS decides what to publish (actual theme colours and the global wallpaper),
when to publish (provider/file events), and how to report or coalesce updates.
Rust implements the bounded filesystem transaction: validation, file locking,
permissions, copy-if-changed, atomic publication and cleanup. It does not choose
a theme, locate a user configuration, schedule mode changes or control greetd.

The thin interface is an explicit subcommand and destination plus one versioned
JSON document on stdin. Successful exit means publication completed, not merely
accepted; nonzero exit means failure, with diagnostics on stderr. Colour and
wallpaper operations are independent, not an all-settings RPC. Reader schemas
reject unknown fields/versions. The production-QML-to-helper integration test
checks the actual palette contract across JS and Rust; changing either side must
keep that test passing rather than silently widening the accepted protocol.

QML code installation is a different, administrative file operation, implemented
by the portable `nullshell-install-greeter` script. It does not use or extend these
mutable-data APIs. Its resource-interface marker covers entry layout and the
existing native greetd/data interfaces; it is not a guarantee for arbitrary custom
Qt imports. The greeter still has no dependency on the Rust exporter at runtime.

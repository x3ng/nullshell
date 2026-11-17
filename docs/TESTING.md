# Testing without replacing the host desktop

## Portable checks first

With Python 3, Cargo and Quickshell installed, no Nix evaluation is needed:

```sh
make check
make check-command
make check-backend
cargo clippy --locked --manifest-path backend/Cargo.toml -- -D warnings
# Inside a Wayland compositor (starts and closes only its fixture preview):
make check-preview
python3 tests/test_panel_preview.py --screenshots /tmp/nullshell-preview
```

The preview test requires Quickshell on PATH; screenshots additionally require
`grim`. `--keyboard` additionally uses `wtype`, preferably inside a nested/test
compositor so synthetic keys cannot interfere with other work. It exercises the
same QML panel with mock states, checks routing and settled geometry, selection
identity across title updates, resize/palette changes, logs and process cleanup.
It does not claim to prove hover stability from a result count or screenshot.
The test refuses to attach to an existing preview instance.

`make check-command` additionally requires D-Bus and Python dbus-next (available
in `nix develop`). It stages real search/config/notification/launcher modules in
temporary XDG directories, uses a private session bus and fake systemd-run, and
checks exact/abbreviated/Chinese alias matching, scope filtering, launch errors,
timeout, quiet-period expiry/restart, critical exceptions, transient/excluded
notifications, disk-disabled history and corrupt-state preservation. The Nix
wrapper is `checks.<system>.command-panel`. It does not launch host applications.

The separate `legacyPackages.<system>.tests.launch-vm` integration test uses a
real systemd user manager in a disposable VM. It verifies exec failure feedback,
literal arguments, session environment, working directory, app.slice ownership
and application survival after the Quickshell launch client exits:

```sh
nix build path:.#legacyPackages.x86_64-linux.tests.launch-vm --no-link --max-jobs 1 --cores 2
```

Nix can supply these tools via `nix develop`; it is an optional environment,
not a runtime dependency of these scripts. The isolated config/migration/BlueZ
checks are Python scripts too; their Nix wrappers only provide dependencies and
private buses/directories. NixOS module, PAM, greetd and service-lifecycle
integration are tested separately below.

## Lightweight sandbox checks

```sh
nix flake check path:. --max-jobs 1 --cores 2
```

The preview check exercises greeter, lock, Polkit and connectivity views in both palettes.
Each process receives a temporary HOME/XDG directories, private D-Bus session,
an inaccessible system bus and software/offscreen Qt rendering. Nix sandboxing
separates it from the host session. The test requires successful QML loading,
rejects common QML errors and verifies that the preview remains running.
It also loads the actual `lock/shell.qml` entry offscreen, with its default
unlocked state, to catch component discovery failures that the shared visual
preview cannot detect.
It does not verify pixel appearance or real authentication.

The config check runs the real `ShellConfig.qml` with a synthetic temporary
configuration. It checks schema rejection, missing-file defaults, atomic updates,
last-valid retention and recovery through Quickshell IPC. It loads no desktop,
authentication or device services. The same test can run without Nix by invoking
`tests/test_config.py LOG_PATH` with Python 3 and Quickshell in an isolated
HOME/XDG and D-Bus environment, as set up in `nix/tests/config.nix`.

## NixOS VM smoke test

```sh
nix build path:.#legacyPackages.x86_64-linux.tests.vm \
  --no-link --max-jobs 1 --cores 2 -L
```

The VM uses two virtual CPUs and 2 GiB RAM, with no physical-device passthrough.
It checks that a preview is not automatically started merely by installing it,
then starts and stops it as an ordinary user. Its service is defined only inside
the test VM; it does not install a service on the host.
Test reports remain in Nix outputs, not in Git. Nix store dependencies may be
downloaded, but no host profile is switched.

## Interactive visual previews

`nix run path:.#preview-lock` (also `preview-greeter`, `preview-polkit`) opens a
visual-only window. These entries do not authenticate, lock or execute power
actions. Unlike the sandbox check, an interactive invocation uses the caller's
environment and may read existing wallpaper state. It is not a general sandbox
for arbitrary desktop code. The full desktop entry is not a safe preview.

`./bin/nullshell preview-panel` runs the full production panel with isolated
fixtures directly from source. See [DEVELOPMENT.md](DEVELOPMENT.md) for scenario,
page, width, palette and screenshot commands. It requires Wayland; native mapping
and fixture isolation are checked in the desktop VM rather than inferred from
an offscreen load.

## Real authentication in disposable VMs

```sh
nix build path:.#legacyPackages.x86_64-linux.tests.lock-vm --no-link --max-jobs 1 --cores 2
nix build path:.#legacyPackages.x86_64-linux.tests.greeter-vm --no-link --max-jobs 1 --cores 2
```

The locker test uses a headless Sway compositor to exercise the real Wayland
session-lock protocol and the packaged PAM service: incorrect password stays
secured, correct password unlocks, and the process remains available. This tests
the protocol without claiming Sway support for the full desktop.
The greeter test uses real greetd and Cage: incorrect credentials cannot launch a
session; correct credentials launch the selected session as the test user. It
then restarts greetd, adds a newly available session, and logs in using only a
password to verify the remembered user and session. It checks the greeter-owned
state file's permissions.
Keyboard injection establishes focus before typing; the test accounts and
passwords exist only inside the VM. Neither test installs host services.

The private-bus Bluetooth check covers confirmation/rejection, PIN/passkey,
stale replies, cancellation/EOF, oversized input, foreign callers and BlueZ owner
loss. It needs no real radio. Rust unit tests and clippy cover the helper separately.

## Full desktop and Polkit VM

```sh
nix build path:.#legacyPackages.x86_64-linux.tests.desktop-vm --no-link --max-jobs 1 --cores 2
```

This boots real Hyprland with a virtual GPU, directly launches the desktop, locker, Polkit and sleep bridge,
opens/closes the panel, verifies Keep awake migration and restart persistence,
checks manual appearance availability and wallpaper screen tracking across virtual monitor
creation/removal, and checks separate locker/Polkit process identities. A real Polkit request is
cancelled without executing the privileged command. A second request survives a
desktop restart and succeeds only after authentication. Disconnecting the compositor terminates its direct clients. The setuid pkexec wrapper is enabled explicitly only
inside this VM for the test; the production module does not enable it implicitly.

## Remaining acceptance boundaries

Physical GPU behavior, real Bluetooth hardware and actual laptop suspend/resume
need final hardware acceptance. The Rust sleep bridge's private-bus tests do not
establish real hardware suspend safety.
Do not claim the authentication VMs establish real hardware power behavior.

## Sleep bridge protocol

`make check-session` tests `SessionActions.qml` with fake `busctl`, `systemctl`,
`uwsm` and `loginctl` executables, isolated HOME/runtime and unreachable buses.
It checks logind permission gating, concurrent request rejection, exact command
arguments, UWSM/logind logout selection and failure feedback without a real action.
Panel preview tests separately exercise the power button, confirmation/cancel,
unavailable and busy states, and light/dark screenshots at 440 and 740 pixels.

`make check-sleep` (inside `nix develop` when needed) or
`nix build path:.#checks.x86_64-linux.sleep --no-link --max-jobs 1 --cores 2`
uses a fresh D-Bus daemon as a synthetic system bus. A mock logind transfers real
pipe descriptors and verifies their lifetime before/after lock confirmation,
failure, timeout, resume, stale replies, duplicate startup and owner/session loss.
Lock and resume commands are synthetic Python fixtures; no host locker, PAM,
compositor, location service or sleep action is invoked.

The `legacyPackages.x86_64-linux.tests.lock-vm` test additionally creates a real
logind session in a disposable Sway VM, sends `loginctl lock-session`, waits for
the helper's confirmed lock, rejects a wrong password and verifies PAM unlock.


Appearance synchronization: `make check-appearance` runs real QML file
subscriptions with temporary XDG/shared paths. It checks manual changes, restart
persistence, invalid snapshot recovery, independent
wallpaper events, source-file replacement, fit-only no-copy, byte limits, fixed
slots and cleanup. The Nix `appearance` check runs the same tests. No host service
is contacted. Greeter VM coverage checks source/reader/unrelated-account
permissions and a mode update during an actual greetd authentication conversation.
For visual checks set `NULLSHELL_APPEARANCE_FILE` and `NULLSHELL_WALLPAPER_FILE`
when starting the working-tree greeter preview; these are data inputs, not QML
installation paths. Verify both palettes, wallpaper/no wallpaper and feedback
states; preview loading is not authentication acceptance.

The greeter VM also exercises the portable QML installer through the configured
NixOS wrapper: packaged startup, root-owned installation, unprivileged rejection,
resource-version mismatch, external-link rejection, local-override authentication,
update without restarting the greeter, retention of its pinned resources, and
explicit reset/cleanup back to packaged QML. Installer structure checks never
execute a submitted interface as root. They do not replace working-tree previews
or guarantee authentication for arbitrary custom QML.

Automatic appearance and the native Settings backend have private-bus and
offscreen checks: `make check-settings` and `make check-appearance` (see
[APPEARANCE.md](APPEARANCE.md)). `checks.<system>.settings` tests a synthetic
GeoClue service; the desktop VM verifies real portal routing with the native backend.

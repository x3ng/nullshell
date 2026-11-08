# Testing without replacing the host desktop

## Portable checks first

With Python 3, Cargo and Quickshell installed, no Nix evaluation is needed:

```sh
make check
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
checks Darkman availability and wallpaper screen tracking across virtual monitor
creation/removal, and checks separate locker/Polkit process identities. A real Polkit request is
cancelled without executing the privileged command. A second request survives a
desktop restart and succeeds only after authentication. Disconnecting the compositor terminates its direct clients. The setuid pkexec wrapper is enabled explicitly only
inside this VM for the test; the production module does not enable it implicitly.

## Remaining acceptance boundaries

Physical GPU behavior, real Bluetooth hardware and actual laptop suspend/resume
need final hardware acceptance. The sleep bridge remains hypridle.
Do not claim the authentication VMs establish real hardware power behavior.

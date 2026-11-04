# Testing without replacing the host desktop

## Lightweight sandbox checks

```sh
nix flake check path:. --max-jobs 1 --cores 2
```

The preview check exercises greeter, lock and Polkit views in both palettes.
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

This boots real Hyprland with a virtual GPU, starts the packaged session target,
opens/closes the panel, verifies Keep awake migration and restart persistence,
checks Darkman availability and wallpaper screen tracking across virtual monitor
creation/removal, and checks separate locker/Polkit process identities. A real Polkit request is
cancelled without executing the privileged command. A second request survives a
desktop restart and succeeds only after authentication. Stopping the session
target stops its components. The setuid pkexec wrapper is enabled explicitly only
inside this VM for the test; the production module does not enable it implicitly.

## Remaining acceptance boundaries

Physical GPU behavior, real Bluetooth hardware and actual laptop suspend/resume
need final hardware acceptance. The sleep bridge remains hypridle.
Do not claim the authentication VMs establish real hardware power behavior.

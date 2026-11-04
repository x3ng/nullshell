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

## Required future integration coverage

Before deployment, extend VM tests to real compositor/session-lock, PAM, greetd,
agent cancellation/crash recovery and session-scoped service lifecycle. Use fake
D-Bus services for deterministic BlueZ disconnect, timeout and cancellation tests.
These tests are not implemented by the initial preview smoke test.

Physical GPU behavior, real Bluetooth hardware and actual laptop suspend/resume
need a separate final hardware acceptance pass after isolated tests succeed.
Do not claim VM smoke tests establish those properties.

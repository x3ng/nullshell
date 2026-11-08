# Portable build and installation

The runtime does not require Nix. QML resources are interpreted by Quickshell;
the Bluetooth helper uses standard Cargo with a committed Cargo.lock and an
independent build output. `make build` builds only this helper; QML needs no compilation.

## From a checkout

```sh
make check
./bin/nullshell preview-greeter
./bin/nullshell preview-lock
./bin/nullshell preview-polkit
```

The preview needs Quickshell (currently developed against 0.3.2) and its Qt Quick,
Effects and Window modules. Desktop integration currently targets Hyprland 0.57
Lua APIs. These versions are the initial development baseline, not a tested
compatibility range. Hardware acceptance and host cutover remain separate from package installation.

## Fast UI iteration

See [DEVELOPMENT.md](DEVELOPMENT.md) for the edit/preview/acceptance workflow and
the full-panel preview commands. Do not deploy to inspect trial layouts.

From the checkout, an installed nullshell runtime can load the working QML tree:

```sh
NULLSHELL_DATA_DIR="$PWD" nullshell preview-connectivity
```

Quickshell watches source changes and reloads the preview. No build, release,
flake update or Home Manager switch is needed. This window reuses the desktop's
connection summary and has synthetic connected, disconnected, disabled,
unavailable and long-name states, plus a light/dark switch. It starts no desktop
services and does not change radios or device connections. It checks layout,
not compositor blur or hardware integration.

Without an installed runtime, use the project environment:

```sh
nix develop --command ./bin/nullshell preview-connectivity
```

The same source override works for `preview-lock`, `preview-greeter` and
`preview-polkit`. Use `preview-panel` for the full command panel with synthetic state.
Do not launch a second `desktop` as a preview: it owns real notification,
wallpaper and idle services. Keep release deployment separate from visual
iteration; use the VM tests for session integration.

## Package staging (including Arch PKGBUILD)

```sh
make install PREFIX=/usr DESTDIR="$pkgdir"
```

This installs `bin/nullshell` and `share/nullshell/` without enabling services,
writing user configuration or touching the active session. The common launcher prefers the editable XDG checkout when installed without
a fixed resource override, and otherwise falls back to installed resources. For development or special
packaging, `NULLSHELL_DATA_DIR` explicitly overrides the resource directory.
Use a clean package staging directory; this is not an in-place upgrade manager.

Current desktop adapters use systemd/util-linux tools, hypridle, coreutils, bash, the Rust helper, BlueZ tools,
NetworkManager tools, brightnessctl, Hyprland and Darkman. The on-screen keyboard
uses optional wvkbd. Audio/media/battery use the corresponding Quickshell APIs and
system services. Dependency names and optional feature handling will be refined
when the adapters are separated; do not interpret this resource package as a
complete replacement for host configuration yet.

Nix builds use the same `bin/nullshell` launcher and QML tree. Only `flake.nix`
and `nix/` contain Nix-specific packaging, dependency paths and VM definitions.
Application code must not invoke Nix or embed `/nix/store` paths.

Arch packaging should declare runtime dependencies and call the staging target;
it must not invoke `nix build`. A release PKGBUILD will be added once the runtime
contract is settled, rather than publishing an incomplete
package now.

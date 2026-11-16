# Runtime dependencies and host services

nullshell installs its own runtime and the tools it invokes. Installing a package
does not select a network backend, enable host daemons, deploy user QML or start a
session. NixOS integration is a separate, explicit choice; other distributions
must provide equivalent service registration and permissions.

## Runtime tools

The current Nix runtime includes upstream Quickshell, nullshell-helper, Bash,
coreutils, systemd tools, util-linux, brightnessctl, Hyprland (for hyprctl), and
wvkbd. These are executable dependencies, not instructions to enable their
services. QML and the Rust helper remain independently packaged.

| Tool | Consumer |
| --- | --- |
| Quickshell and its Qt modules | Desktop, locker, Polkit and preview QML |
| nullshell-helper | BlueZ pairing, solar/location, appearance exports, Settings portal and sleep bridge |
| Bash, coreutils, util-linux | Launch/install scripts, locking and file operations |
| systemd tools | Session actions, capability queries, idle inhibition, backlight event monitoring and application scopes |
| brightnessctl | Backlight slider and idle dim/restore |
| hyprctl | Current Hyprland desktop adapter, display power and keyboard placement |
| wvkbd-mobintl | On-screen keyboard; optional feature, included in the Nix runtime |

UWSM is detected at runtime for session logout; it is a consumer session choice,
not required. The configured terminal is needed for terminal applications, not
for networking. No nmcli, nmtui or bluetoothctl subprocess is used.

## Feature service requirements

| Feature | Host requirement | Ownership |
| --- | --- | --- |
| Wi-Fi | NetworkManager system D-Bus service | Quickshell Networking owns device state and ordinary operations |
| Bluetooth | BlueZ system D-Bus service | Quickshell Bluetooth owns devices; helper supplies an on-demand Agent1 for pairing |
| Audio/media | PipeWire with session policy; MPRIS-capable applications | Quickshell native services |
| Battery | UPower | Quickshell native service |
| Power profiles | Compatible power-profiles-daemon D-Bus API | Quickshell native service; panel probes availability |
| Lock/sleep/session actions | Wayland session-lock, logind, PAM and Polkit | Independent locker and sleep bridge; host supplies authorization policy |
| Application appearance | xdg-desktop-portal and explicit Settings backend routing | nullshell publishes preferences only |
| Automatic location | GeoClue, only when selected | Fixed coordinates require no GeoClue |
| Greeter | greetd, dedicated account, Cage, PAM and installed greeter resources | Explicit system integration, separate from user QML |

Wi-Fi currently targets NetworkManager, not a generic network backend. An
iwd-only/networkd host does not gain Wi-Fi controls by installing nullshell.
Installing NetworkManager or BlueZ client binaries alone does not satisfy these
service requirements. Missing radios/services leave the respective controls
unavailable; nullshell does not install, start or replace a network service.

The panel supports nearby open, OWE and personal-password Wi-Fi, saved network
activation, disconnect and forget. Enterprise/legacy profile creation, hidden
network setup, VPN and general IP/DNS editing are not implemented. Unsupported
new authentication types show an explanation and cannot be connected from the
panel. Consumers can configure profiles with their preferred independent network
tool. Saved profile activation still depends on NetworkManager having the
necessary credentials; nullshell does not provide a general secrets agent.

Bluetooth discovery, connection, pairing and removal stay in the panel. No
replacement BlueZ daemon or general-purpose Bluetooth command wrapper is shipped.

## Distribution packaging

Use `make install` for runtime commands and activation descriptors. Declare the
runtime tools above using distribution package names; optional keyboard support
may be a recommended dependency. Document NetworkManager/BlueZ and other feature
services as feature requirements rather than unconditionally enabling them in a
package install hook. Build/test dependencies such as Cargo, Python, labwc and
wtype are not runtime requirements.

The Nix runtime exposes tools on PATH so native `quickshell -c nullshell` works
without hidden launcher setup. `programs.nullshell.enable` additionally configures
PAM, Polkit and UPower. Portal, GeoClue and greetd integration have separate opt-ins.
It does not enable NetworkManager, BlueZ, PipeWire or a power-profile daemon;
consumers select these in their host configuration. Personal lid/power-key policy,
session startup and QML/configuration ownership remain with the consumer.

Do not copy every desktop application into this dependency list: clipboard,
screenshot, file-manager and theme tools belong to consumers unless a nullshell
feature actually invokes them.

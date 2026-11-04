# Releases

## v0.1.0

First source release of the independent nullshell project (MIT).

- Separately packaged desktop and greeter, with shared QML resources.
- Command panel, notifications, wallpaper, OSD, idle policy, locker and Polkit UI.
- Independent authentication processes, session-scoped systemd units and a
  hypridle sleep bridge; installing packages does not start the desktop.
- Versioned configuration with validation/hot reload and one-time legacy state
  migration that preserves existing destinations.
- Rust BlueZ Agent1 helper for bounded, device-specific pairing requests.
- Portable Make/Cargo installation and optional NixOS/Home Manager modules.

Validation: offscreen previews, configuration/state tests, mock BlueZ protocol
checks and NixOS VMs exercising greetd, session-lock/PAM, Hyprland, Polkit,
monitor hotplug and appearance provider integration. See TESTING.md for commands.
The tested platform is x86_64-linux; aarch64 outputs are provided but not validated
on hardware. Physical Bluetooth, GPU and laptop suspend/resume acceptance remains.

This is a source release, not a prebuilt binary distribution. Nix builds the
locked sources; portable installations use Make/Cargo. Keep the current desktop
running until the documented TTY cutover in DEPLOYMENT.md.

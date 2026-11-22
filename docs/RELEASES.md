# Releases

## Unreleased

Command-panel reliability and small capability additions, preserving the empty
idle desktop and existing homepage layout:

- Scroll keyboard focus into view and support tray activation/menu navigation.
- Report bounded application-launch failures through independent user services.
- Match conservative name abbreviations and configurable application/command aliases.
- Add one-hour notification quiet periods with critical-alert exceptions and
  restart-safe expiry. History defaults to seven days (still at most 50 entries),
  excludes transient hints by default, and supports opt-out and per-app exclusions.
- Schedule automatic appearance offline from the time zone or fixed coordinates;
  IP location is optional. Publish the effective preference through Settings.
- Add an opt-in Hyprland display editor with trial, confirmation and rollback.
  Hyprland restores confirmed layouts without a running shell.
- Add GUI idle timer editing with per-domain persistence and reset to
  configuration defaults; the system suspend and lid policy is unchanged.

Validation: portable checks, private-bus configuration/command tests, isolated
keyboard previews with inspected 440/740 px screenshots in both palettes, and a
real systemd application-launch VM. Native tray application compatibility and
physical-device acceptance remain separate from synthetic preview checks.
The display and idle pages have their own preview and state tests. Nested
Hyprland covers display persistence and virtual hotplug; it does not substitute
for real external connectors, lid or resume testing.

Keep upstream Quickshell and native named configuration discovery. Install the
helper/runtime independently of user QML; greeter resources remain separate.
Configuration management, including optional consumer-owned Home Manager use,
is an explicit user choice. Legacy state migration is now an explicit command.

The entries below describe historical releases, not current acceptance results.
This checkpoint does not create or restore release tags.

## v0.2.0 — 2026-11-05

Consolidated desktop release following the v0.1.1 baseline.

- Flat tonal materials and native rounded desktop blur; no full-screen command
  panel scrim or separate surface fade before the blur tint appears.
- Compact connection details, workspaces below full-width content, matching
  workspace/tray icon sizes, wrapping workspaces and single-column controls at
  narrow widths. Remove redundant workspace management chrome.
- Full `preview-panel` entry reuses the production LauncherPanel with injected
  clock, screen and synthetic services. Source edits reload without publishing,
  updating consumer lockfiles or activating host services.
- Fix greeter, locker and Polkit preview windows so they actually map; fix hidden
  page minimum widths that caused narrow panel contents to overflow.
- Portable Python preview tests shared by local development and the NixOS VM.
  Nix provides optional tools and system integration checks, not the test logic.

Validation on x86_64-linux: portable deployment/migration checks, Rust unit tests
and clippy, all flake checks (including private-bus Bluetooth), and desktop/Polkit,
session-lock/PAM and greetd VMs passed. Native panel previews were inspected at
740 and 440 px, including long labels, multiple applications per workspace,
wrapped rows and both palettes. VM checks cover keyboard selection retention,
actual preview mapping and production-service isolation. Physical Bluetooth,
GPU and suspend behavior remain hardware acceptance boundaries; aarch64 builds
and other distributions have not been exercised in this release run.

This is a source release. Publishing it does not update consumer configurations
or activate a host. The withdrawn experimental v0.1.2–v0.1.10 tags are not reused.

## v0.1.1

The greeter now remembers the last successfully authenticated user and session.
NixOS stores this small JSON state under a dedicated greeter-owned directory;
neither passwords nor desktop-user files are read. The greetd VM verifies a
second login after a greeter restart and an added session.

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

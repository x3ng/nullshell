# Deployment contract

Install and activation are separate operations. Packages do not start a session.
`nullshell session-start` is called from Hyprland after its environment is ready;
it imports the display environment into the user manager and starts
`nullshell-session.target`. Every component requires a Hyprland/Wayland environment.
There are no global WantedBy links. UWSM/graphical-session.target owns teardown;
non-UWSM integrations must stop nullshell-session.target on session exit.

Desktop, locker and Polkit have independent services. Restarting the desktop
service does not restart authentication components. Never restart a locked locker
or an active Polkit agent. `nullshell lock` returns success only after the
compositor reports the session secured; it exposes no unlock command.

The target also starts `nullshell-sleep.service`, which runs hypridle for logind
lock/suspend coordination. It has no idle timers and conflicts with another
hypridle.service. Quickshell owns dim/lock/display-off timers. A Rust replacement
for this bridge is not required for v0.1 and must pass dedicated sleep tests before
replacing hypridle.

The desktop unit requests `darkman.service` for automatic appearance changes.
Install its user unit when using this provider; a missing provider does not block
the desktop because this is a Wants dependency. Host-specific location and
appearance policy remain external configuration.

## State

The desktop and locker perform a locked, one-time import of known files from
`$XDG_STATE_HOME/quickshell` to `$XDG_STATE_HOME/nullshell`. Existing target files
win. Sources are retained, permissions on copied files are 0600, and a completion
marker prevents cleared state from reappearing. Legacy wallpaper defaults are
likewise copied from the old XDG config location. `nullshell migrate-state` can
perform this independently. Preview and greeter never perform migration.

## Nix

Import `homeManagerModules.default`, set `programs.nullshell.enable = true` for
user packages/units; separately import `nixosModules.default` and enable
`programs.nullshell.enable` for PAM/Polkit/UPower integration. Enable
`programs.nullshell.greeter.enable` only if replacing the display manager is
intended. Set `programs.nullshell.editable = true` in Home Manager to install
`packages.runtime` instead of the bundled desktop. Clone the QML repository to
`$XDG_CONFIG_HOME/quickshell/nullshell` (default `~/.config/quickshell/nullshell`).
The module never creates or overwrites that checkout. All desktop/locker/Polkit
launchers and IPC calls resolve the same directory. `NULLSHELL_CONFIG_DIR` can
explicitly select another checkout when supplied consistently to all processes.

The greeter remains a packaged system-owned snapshot. Missing local QML fails
with a resource error; the editable runtime does not silently start an old UI.
Helper and runtime updates require deployment; QML edits do not. For the initial
migration from bundled QML, deploy the new units and log out/in (or reboot).
Do not live-restart authentication components or mix old locker paths with new IPC.

## Other distributions

`make install` installs portable resources and user units. Distribution packages
must provide their native PAM configuration as `/etc/pam.d/nullshell-lock`.
An Arch-specific include file is in `integration/pam/nullshell-lock.arch`; it is
not installed on other distributions automatically. Install Quickshell, hypridle,
systemd/util-linux tools and the documented feature dependencies. Enable greetd
with a dedicated greeter account, Cage and `nullshell greeter` as appropriate.
Do not run a second notification daemon or Polkit agent in the same session.

The Lua adapter ships with the resources and is loaded by absolute resource path;
it does not require personal dotfiles Lua modules. The existing layer namespaces
are retained for compatibility with compositor layer rules.

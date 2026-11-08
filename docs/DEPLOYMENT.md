# Deployment contract

Installation does not start processes or install Quickshell user services.
The compositor starts each process once, directly. For Hyprland 0.57 Lua:

```lua
hl.on("hyprland.start", function()
  hl.exec_cmd("systemctl --user start darkman.service") -- optional appearance provider
  hl.exec_cmd("nullshell locker --no-duplicate")
  hl.exec_cmd("nullshell polkit --no-duplicate")
  hl.exec_cmd("nullshell desktop --no-duplicate")
  hl.exec_cmd("nullshell sleep-bridge")
end)
```

Do not also run the old nullshell units, another notification owner, Polkit agent
or hypridle. Quickshell prevents duplicate configurations with `--no-duplicate`;
the sleep bridge holds a per-Wayland-display flock. There is no automatic crash
restart. Direct clients exit on Wayland disconnection; the host's UWSM session
also provides cgroup cleanup. Manual terminal launches may use `--daemonize`;
no `disown` is needed for compositor-launched processes.

Desktop, locker and Polkit are independent processes. Restarting the desktop
does not restart authentication components. Never restart a locked locker or an
active Polkit agent. `nullshell lock` starts an absent locker directly, then waits
for the compositor to confirm a secured session. Failure is reported; relaunching
a crashed locker is not a guarantee of recovering an abandoned session lock.

`nullshell sleep-bridge` runs hypridle for logind lock/suspend coordination, with
no idle timers. Quickshell owns dim/lock/display-off timers. The Bluetooth helper
is an on-demand process and requires no service. A future persistent helper must
justify its own lifecycle independently; it does not supervise Quickshell.

Darkman may keep its upstream service; start it explicitly from the session when
using that provider. Host-specific location and appearance policy remain external.

## State

The desktop and locker perform a locked, one-time import of known files from
`$XDG_STATE_HOME/quickshell` to `$XDG_STATE_HOME/nullshell`. Existing target files
win. Sources are retained, permissions on copied files are 0600, and a completion
marker prevents cleared state from reappearing. Legacy wallpaper defaults are
likewise copied from the old XDG config location. `nullshell migrate-state` can
perform this independently. Preview and greeter never perform migration.

## Nix

Import `homeManagerModules.default`, set `programs.nullshell.enable = true` for
user runtime packages; separately import `nixosModules.default` and enable
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
migration from bundled QML, run Home Manager switch to remove the old unit links, then log out/in or reboot.
Existing old processes are not stopped during activation; do not manually start
the new processes in that same session.
Do not live-restart authentication components or mix old locker paths with new IPC.

## Other distributions

`make install` installs portable resources and launchers, without user units. Distribution packages
must provide their native PAM configuration as `/etc/pam.d/nullshell-lock`.
An Arch-specific include file is in `integration/pam/nullshell-lock.arch`; it is
not installed on other distributions automatically. Install Quickshell, hypridle,
systemd/util-linux tools and the documented feature dependencies. Enable greetd
with a dedicated greeter account, Cage and `nullshell greeter` as appropriate.
Do not run a second notification daemon or Polkit agent in the same session.

The Lua adapter ships with the resources and is loaded by absolute resource path;
it does not require personal dotfiles Lua modules. The existing layer namespaces
are retained for compatibility with compositor layer rules.

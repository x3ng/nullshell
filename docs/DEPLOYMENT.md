# Deployment contract

Installation does not start processes or install Quickshell user services.
The compositor starts each process once, directly. For Hyprland 0.57 Lua:

```lua
hl.on("hyprland.start", function()
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
the user's native hypridle configuration (`$XDG_CONFIG_HOME/hypr/hypridle.conf`).
The runtime does not install that file or pass a configuration path. Configure
lock/sleep hooks in independently managed dotfiles; omit idle timers when
Quickshell owns dim/lock/display-off timers. The Bluetooth helper
is an on-demand process and requires no service. A future persistent helper must
justify its own lifecycle independently; it does not supervise Quickshell.

Appearance is owned and persisted by the shell, with optional solar scheduling.
The nullshell Settings portal backend publishes the effective colour preference.
There is no parallel GSettings writer. Applications that bypass the Settings
portal are outside this publication contract. Fixed coordinates need no location
service; GeoClue is optional. See [APPEARANCE.md](APPEARANCE.md).

## State

Only an explicit `nullshell migrate-state` command performs a locked, one-time import of known files from
`$XDG_STATE_HOME/quickshell` to `$XDG_STATE_HOME/nullshell`. Existing target files
win. Sources are retained, permissions on copied files are 0600, and a completion
marker prevents cleared state from reappearing. Legacy wallpaper defaults are
likewise copied from the old XDG config location. Normal startup, lock requests, previews and greeter never perform migration.

## Nix

Import `nixosModules.default` and enable `programs.nullshell.enable` to install
one complete runtime plus PAM/Polkit/UPower environment. Enable portal, GeoClue
and greeter integration explicitly when needed. There is currently no dedicated
Home Manager module. Consumers may manage their QML/configuration through Home
Manager explicitly; installation does not select or require a configuration manager.
The default package is the runtime; it contains no desktop QML snapshot and does
not replace upstream Quickshell with a wrapper.

Maintain QML separately under Quickshell's standard configuration directories.
`nullshell desktop`, `locker`, `polkit` and IPC use native names `nullshell`,
`nullshell/lock` and `nullshell/polkit`. No custom directory inference or fallback
is used. The greeter consumes only its separate system-owned resource snapshot.
Preview commands alone accept `NULLSHELL_DATA_DIR` for an explicit source tree.

Build/evaluation never authorizes activation. Install accepted runtime changes,
then use a fresh login for the updated session startup. Never restart active
authentication components or start new instances alongside old ones.

## Other distributions

`make install` installs portable runtime commands, without user units. Distribution packages
must provide their native PAM configuration as `/etc/pam.d/nullshell-lock`.
An Arch-specific include file is in `integration/pam/nullshell-lock.arch`; it is
not installed on other distributions automatically. Install Quickshell, hypridle,
systemd/util-linux tools and the documented feature dependencies. Enable greetd
with a dedicated greeter account, Cage and `nullshell greeter` as appropriate.
Use `make install-assets` explicitly for the system-owned greeter resources.
Do not run a second notification daemon or Polkit agent in the same session.

The Lua adapter ships with the resources and is loaded by absolute resource path;
it does not require personal dotfiles Lua modules. The existing layer namespaces
are retained for compatibility with compositor layer rules.

## Optional local greeter QML override

After deploying the module/runtime support once, use
`sudo nullshell-install-greeter --source "$PWD"` from the reviewed checkout to
install code for the next greeter launch. The module supplies the destination;
`--reset` explicitly returns to packaged QML. Neither command restarts services
or modifies the mutable appearance/wallpaper snapshots. See
[DEVELOPMENT.md](DEVELOPMENT.md#local-greeter-qml-installation) for resource limits,
compatibility, cleanup, portable installation and TTY recovery.

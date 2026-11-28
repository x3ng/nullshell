# Deployment contract

Installation does not start processes or install Quickshell user services.
Configure the session to start each process once, using Quickshell directly.
For example, in Hyprland 0.57 Lua:

```lua
hl.on("hyprland.start", function()
  hl.exec_cmd("quickshell -c nullshell/lock --no-duplicate")
  hl.exec_cmd("quickshell -c nullshell/polkit --no-duplicate")
  hl.exec_cmd("quickshell -c nullshell --no-duplicate")
  hl.exec_cmd("nullshell sleep-bridge")
end)
```

Prefer calling native `quickshell -c ...` and `quickshell ipc -c ...` directly in
compositor startup and keybinds so no wrapper process sits between the compositor
and Quickshell. `nullshell desktop`, `locker`, `polkit` and `ipc` remain optional
compatibility shorthands for those same `quickshell -c` commands. `nullshell lock`
(`nullshell-lock`) and `nullshell sleep-bridge` (`nullshell-helper sleep-bridge`)
are dedicated helpers for OS capabilities Quickshell does not provide (starting an
absent locker and waiting for a confirmed compositor lock, and logind sleep
coordination).

Do not also run the old nullshell units, another notification owner, Polkit agent
or hypridle. Quickshell prevents duplicate configurations with `--no-duplicate`;
the sleep bridge holds a per-logind-session runtime lock. There is no automatic crash
restart. Quickshell clients exit on Wayland disconnection; the host's UWSM session
also provides cgroup cleanup. Manual terminal launches may use `--daemonize`;
no `disown` is needed for compositor-launched processes.

Desktop, locker and Polkit are independent processes. Restarting the desktop
does not restart authentication components. Never restart a locked locker or an
active Polkit agent. `nullshell lock` starts an absent locker directly, then waits
for the compositor to confirm a secured session. Failure is reported; relaunching
a crashed locker is not a guarantee of recovering an abandoned session lock.

`nullshell sleep-bridge` runs the Rust helper for logind lock/suspend coordination.
It holds a delay inhibitor and calls `nullshell lock`; successful exit of that
command confirms the compositor has secured the session. Lock failure retains
the inhibitor rather than reporting success, but logind's maximum delay still
limits how long sleep can be postponed. Resume reacquires the inhibitor and the
Hyprland launcher requests display power on. No hypridle configuration is read.
Quickshell continues to own dim/lock/display-off timers. Do not run hypridle or a
second sleep bridge alongside it. The helper exits on session removal or logind
owner loss; it does not supervise Quickshell. A logind restart requires restarting
the bridge or starting a new session. See BACKEND.md for the portable CLI.

Appearance is owned and persisted by the shell, with optional solar scheduling.
The nullshell Settings portal backend publishes the effective colour preference.
There is no parallel GSettings writer. Applications that bypass the Settings
portal are outside this publication contract. Automatic mode uses local `tzdata`
by default; fixed coordinates also work offline. Opt-in IP location requires
`curl`. None of these modes requires a system location service.
See [APPEARANCE.md](APPEARANCE.md).

Display editing requires an explicit Hyprland include; installation does not
add it. The shell manages trial and confirmation, while Hyprland restores the
confirmed layout independently. See [DISPLAYS.md](DISPLAYS.md). Idle timeouts
are desktop preferences; no login manager or hardware power policy is changed
by editing them.

## State

Only an explicit `nullshell migrate-state` command performs a locked, one-time import of known files from
`$XDG_STATE_HOME/quickshell` to `$XDG_STATE_HOME/nullshell`. Existing target files
win. Sources are retained, permissions on copied files are 0600, and a completion
marker prevents cleared state from reappearing. Legacy wallpaper defaults are
likewise copied from the old XDG config location. If notifications exist only in
an older shell cache, pass `--notification-cache /path/to/notification_history.json`
on the first migration. The legacy state file takes precedence over that cache. Normal startup, lock requests, previews and greeter never perform migration.

## Nix

Import `nixosModules.default` and enable `programs.nullshell.enable` to install
one complete runtime plus PAM/Polkit/UPower environment. Portal and greeter
integration are explicit opt-ins. There is currently no dedicated
Home Manager module. Consumers may manage their QML/configuration through Home
Manager explicitly; installation does not select or require a configuration manager.
The default package is the runtime; it contains no desktop QML snapshot and does
not replace upstream Quickshell with a wrapper.

NetworkManager and BlueZ services remain explicit host choices; this module does
not enable them. Their command-line tools are not included as direct runtime
dependencies. See [the dependency contract](DEPENDENCIES.md) for each feature's
requirements and the current network panel's supported operations.

Maintain QML separately under Quickshell's standard configuration directories.
`nullshell desktop`, `locker`, `polkit` and IPC use native names `nullshell`,
`nullshell/lock` and `nullshell/polkit`. No custom directory inference or fallback
is used. The greeter consumes only its separate system-owned resource snapshot.
Preview commands alone accept `NULLSHELL_DATA_DIR` for an explicit source tree.
The system greeter takes its Wayland session entries from `XDG_DATA_DIRS`, not
user data directories. The NixOS module adds the system profile to that search.

Build/evaluation never authorizes activation. Install accepted runtime changes,
then use a fresh login for the updated session startup. Never restart active
authentication components or start new instances alongside old ones.

## Other distributions

`make install` installs portable runtime commands, without user units. Distribution packages
must provide their native PAM configuration as `/etc/pam.d/nullshell-lock`.
An Arch-specific include file is in `integration/pam/nullshell-lock.arch`; it is
not installed on other distributions automatically. Install Quickshell,
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

# Power and session menu

The panel's power button and the searchable “Power and session” action open the
same menu: lock, sleep, log out, restart and shut down. Lock uses the existing
locker action. Sleep requests systemd suspend; the independent sleep bridge
coordinates compositor lock confirmation. Logout, restart and shutdown require
an explicit confirmation, which is cleared when leaving the page.

`SessionActions.qml` queries logind's CanSuspend/CanReboot/CanPowerOff through
`busctl`. Both `yes` and `challenge` are available; normal Polkit authorization
still applies. Unsupported or denied actions are disabled. Requests use bounded
Quickshell Process instances, with an immediate busy guard and visible errors.
Successful systemctl exit means the job was accepted, not that shutdown completed.
No force flags or inhibitor bypass are used.

Logout uses `uwsm stop` when its active-session check succeeds; otherwise it
terminates the explicit `XDG_SESSION_ID` through loginctl. No session ID and no
active UWSM session means logout is unavailable. The UI constructs no shell
commands; the QML adapter owns fixed argument arrays. These existing system tools
need no Rust helper wrapper. The physical power key and host logind policy remain
under external configuration.

The standalone panel preview injects a synthetic session adapter. Its power
controls never execute host commands or read host power capabilities.

## On-demand tools

Open **Workspaces** and choose the keyboard button to read the current Hyprland
bindings. Filter by key combination, description, submap or dispatcher. Entries
are read-only. Hyprland may supply only a dispatcher name for a Lua binding.

Search for **Capture a region** or bind `nullshell ipc call capture region` in
your compositor. The desktop closes its panel before selection. Escape cancels.
The image is saved to the XDG Pictures directory under `Screenshots/`, with
`~/Pictures` as fallback. The notification offers **Open image**.

In **Power and session**, enter a duration in minutes and choose **Start**.
The expiry survives shell restarts. **End timer** preserves any permanent setting. Clicking an active Keep
awake button resumes idle behavior immediately. IPC also accepts a duration in
minutes, for example `nullshell ipc call idle keepAwakeFor 30` (1–1440, or 0 to
cancel). `idle status` exposes the permanent choice and the expiry in epoch ms.

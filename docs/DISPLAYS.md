# Hyprland display profiles

Nullshell discovers and previews display profiles. Hyprland loads confirmed
layouts itself, even when the desktop shell is stopped. No separate monitor
daemon is needed. This integration is **off by default**. Keep Hyprland's
preferred/automatic mode, position and scale as the fallback, and do not run
another profile manager or load another manager's generated rules alongside it.

## Configure and inspect without changing the desktop

Run `nullshell-helper displays outputs` to list the connector names, stable keys
and available modes for currently connected outputs. Create a profile file at
`$XDG_CONFIG_HOME/nullshell/display-profiles.json` (defaulting to
`~/.config/nullshell/display-profiles.json`). An example with synthetic keys:

```json
{
  "version": 1,
  "profiles": [{
    "name": "desk",
    "outputs": [
      {"key": "example|panel", "name": "eDP-1", "enabled": true, "width": 1920, "height": 1080, "refresh": 60},
      {"key": "example|external|sample", "name": "DP-1", "enabled": true, "width": 2560, "height": 1440, "refresh": 60, "x": 1920}
    ],
    "workspaces": [{"workspace": "2", "output_key": "example|external|sample", "persistent": true}]
  }]
}
```

Use `mirror_of` with another enabled output's key to mirror it. Positions
(`x`, `y`) default to zero, `scale` to 1, and `transform` to 0. A disabled output
does not need a mode. Keep profile files private if keys contain serial numbers.
Preview matching without applying anything:

```sh
nullshell-helper displays plan "${XDG_CONFIG_HOME:-$HOME/.config}/nullshell/display-profiles.json"
```

Plans require an exact connected output set and a supported mode on each display
that advertises modes. Matching uses monitor make/model/serial when available,
not just the connector; saved connectors break a tie. Planning never changes
the running layout or automatically confirms a candidate.

## Opt in

After stopping the old manager and removing its generated include, add this
explicit include after the static monitor rules in `hyprland.lua`:

```lua
local config = os.getenv("XDG_CONFIG_HOME")
if not config or config == "" then config = os.getenv("HOME") .. "/.config" end
_G.nullshellDisplayStore = config .. "/nullshell/hyprland-displays.lua"
local restore = loadfile(_G.nullshellDisplayStore)
if restore then restore() end
```

On first use the file doesn't exist; Hyprland uses its native fallback. Reload
Hyprland, then set `"displays":{"mode":"manual"}` in nullshell's version-1
`config.json`. Use the desktop IPC target:

```sh
nullshell ipc call displays status
nullshell ipc call displays apply PROFILE_NAME
nullshell ipc call displays confirm
nullshell ipc call displays revert
```

`apply` starts a 15-second output-only trial and leaves disk untouched. Run
`confirm` after `status` reports `verified: true` **and** the physical display
looks usable. Confirmation installs the loader on first use and atomically
updates the layout record for the connected topology. Hyprland reloads to apply
the confirmed layout and its workspace rules. Timeout, explicit `revert`, or
shell exit during the trial restores the previous confirmed layout, or the
native fallback when this topology has not been confirmed.

On startup, reload and monitor changes, Hyprland checks the exact connector set,
monitor descriptions, serials and advertised modes before applying a saved
record. When no confirmed record matches, the native fallback stays active.
The legacy `auto` value is treated as `manual`: only a user confirmation saves
a profile, and Hyprland automatically selects previously confirmed layouts.
Setting mode to `off` disables editing in nullshell, not the explicit Hyprland
include. Remove that include to stop all confirmed-layout loading. Saved files
can contain serial numbers, just like the profile file; keep them private.
There is no separate lid policy, and this does not change logind's behaviour.

## Tests

`make check-displays` or `nix build .#checks.x86_64-linux.displays` runs the
Rust helper and actual QML policy against synthetic output events, plus a Lua
watchdog test. It never changes the host desktop. On a machine with a render
node and the listed compositor tools, `python3 tests/test_displays_nested.py
backend/target/debug/nullshell-helper` additionally verifies restoration without
the shell, rollback after shell exit, and virtual hotplug in real nested Hyprland.
Before retiring a working manager, test each actual connector,
including mirrors and any workstation/dock or clamshell use.

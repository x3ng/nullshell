# Hyprland display profiles

Nullshell can match saved display profiles to connected Hyprland outputs and
apply them from the existing desktop process. It does not start another daemon.
This integration is **off by default** and uses Hyprland's Lua IPC API; retain a
working static monitor rule as the fallback. Do not enable it alongside another
monitor profile manager or include a file that the other manager still owns.

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
not just the connector; saved connectors break a tie. If several plans still
tie, nullshell leaves the static layout in place until one is chosen manually.

## Opt in

Set `"displays":{"mode":"manual"}` in the existing version-1 nullshell
`config.json`. Once the old manager is stopped and its generated include is
removed, use the desktop IPC target:

```sh
nullshell ipc call displays status
nullshell ipc call displays apply PROFILE_NAME
nullshell ipc call displays confirm
nullshell ipc call displays revert
```

`apply` starts a 15-second trial. Run `confirm` after `status` reports
`verified: true` **and** the physical display looks usable. Otherwise the
compositor's own timer restores the static Hyprland configuration even if the
nullshell process exits. `revert` also returns to that baseline, not to a prior
runtime override. Confirmed rules live in Hyprland, so restarting nullshell alone
does not erase them. A Hyprland configuration reload resets manual overrides.

Set `"displays":{"mode":"auto"}` only after testing the profiles. In this
mode, startup, compositor reloads and output changes trigger reconciliation;
a uniquely matched layout is confirmed only if compositor readback agrees.
Restarting nullshell with a confirmed, unchanged layout adopts it without
reloading Hyprland.
Connecting a new or ambiguous set restores the static layout. Set mode to `off`
to stop desktop management. There is no separate lid-position policy here; a
lid or resume event only triggers matching when the compositor reports an
output change. This does not change logind's suspend or lock policy.

## Tests

`make check-displays` or `nix build .#checks.x86_64-linux.displays` runs the
Rust helper and actual QML policy against synthetic output events, plus a Lua
watchdog test. It never changes the host desktop. On a machine with a render
node and the listed compositor tools, `python3 tests/test_displays_nested.py
backend/target/debug/nullshell-helper` additionally uses real nested Hyprland
and virtual outputs, without touching the host compositor. Before retiring a working
manager, test manual confirmation and fallback on each actual connector,
including mirrors and any workstation/dock or clamshell use.

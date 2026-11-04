# Configuration v1 (initial slice)

The desktop reads `$XDG_CONFIG_HOME/nullshell/config.json`, falling back to
`~/.config/nullshell/config.json`. It never writes this file. Maintain it by hand
or from dotfiles; Nix is not required. Greeter does not load this user config.

```json
{
  "version": 1,
  "terminal": ["kitty", "--"],
  "idle": {
    "dimSeconds": 150,
    "lockSeconds": 300,
    "displayOffSeconds": 600
  }
}
```

`version` is required. Other fields are optional and merge into package defaults
on every successful read, not into the previous configuration. Unknown keys and
versions are rejected to expose spelling errors and incompatible configuration.

- `terminal` is an argv array, never a shell command. `[]` disables terminal
  launches. The executable must be nonblank; at most 32 arguments are accepted,
  each at most 4096 characters and without NUL. Installing the terminal is the
  user's responsibility; choose the argument separator supported by that terminal.
- Idle values are integer seconds from 1 to 86400, satisfying
  `dimSeconds < lockSeconds < displayOffSeconds`. They are absolute idle
  deadlines, not delays added together. Keep awake continues to suspend all
  automatic idle actions and is persisted separately.

The configuration is watched and valid changes apply live. Changing idle
thresholds changes native idle monitors and may cause idle actions based on the
current session inactivity; this is not a guarantee of a fresh grace period.
Idle monitoring waits for both configuration and persisted Keep awake loading.
Invalid updates retain the last valid snapshot and emit an error for the shell
notification UI. Invalid configuration at first startup uses package defaults.
Missing files at first startup are normal. Removing a previously loaded file
retains that process's snapshot; use `{"version":1}` to reset explicitly.

The authoritative parser/defaults are `qml/ConfigRules.js`; `ShellConfig.qml`
owns file loading and publication. Pages do not read files. This slice covers
terminal and idle configuration only. Wallpaper, theme, greeter configuration
remain separate settings domains. Legacy state migration is documented in
[DEPLOYMENT.md](DEPLOYMENT.md).

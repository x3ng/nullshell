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

The authoritative parser/defaults are `ConfigRules.js`; `ShellConfig.qml`
owns file loading and publication. Pages do not read files. This slice covers
terminal and idle configuration only. Wallpaper, theme, greeter configuration
remain separate settings domains. Legacy state migration is documented in
[DEPLOYMENT.md](DEPLOYMENT.md).

The greeter stores only the last successfully authenticated user and session ID
in its dedicated account's state file. On NixOS this is
`/var/lib/nullshell-greeter/last-login.json` (directory mode 0700, file mode 0600).
Other distributions can set `NULLSHELL_GREETER_STATE_FILE` to a writable path owned
by the greeter account. Missing or invalid state falls back to an empty user and
the available session list. Passwords are never stored, and the greeter does not
read a desktop user's home directory.

## Appearance snapshots (version 1)

Darkman remains the user-session mode provider, including automatic solar changes,
manual changes and the application Settings portal. The desktop exports its actual
`Theme.qml` colours and observed mode whenever they change, when greeter sync is
enabled. Lock and Polkit retain their existing user-session theme and
`appearance-mode` state; they do not consume the greeter's shared snapshots.
Layout, typography and executable QML are not part of this data protocol.

The snapshot has exactly `version: 1`, `mode: "dark" | "light"`, and `colors`.
`AppearanceRules.js` defines the complete colour keys; values are `#RRGGBB` or
Qt's `#AARRGGBB`. Unknown versions/fields, missing colours and invalid colours are
rejected. A missing first snapshot uses the packaged default; later invalid or
removed snapshots keep the last valid in-memory appearance. The snapshot is data,
not a path to a user theme script. Wallpaper uses a separate descriptor and event
stream, described below. A colour update never starts wallpaper export.

Optional NixOS integration:

```nix
programs.nullshell.greeter = {
  enable = true;
  appearance.sourceUser = desktopUser; # your existing account declaration
  # appearance.directory = "/var/lib/nullshell-appearance";
};
```

`sourceUser = null` (default) disables cross-account export. The module creates a
setgid directory owned by the source user with greeter group read/traverse access
(2750), and supplies its path to both processes. The source user can replace theme
data; greeter cannot write it. It is separate from the greeter-owned authentication
state directory. No user's HOME is exposed to greeter, and no personal name/path is
embedded in QML. Changing the source account requires updating the account option
and activating the system configuration; changing the user's XDG directories does
not alter the greeter's read interface. Moving the shared directory starts with a
fresh snapshot when the desktop next publishes.

Portable installations use the same interface:

- Supply `NULLSHELL_APPEARANCE_SOURCE_USER` and
  `NULLSHELL_APPEARANCE_EXPORT_FILE` to the desktop environment. Export is enabled
  only when `USER` matches the designated source. Filesystem permissions enforce
  access; the environment comparison is not authorization.
- Supply `NULLSHELL_APPEARANCE_FILE` to greeter with the same destination.
- Provision a dedicated directory owned by that user, setgid to a group readable
  by greeter, mode 2750. Do not grant access to the greeter's login state directory.
- The ordinary-user `nullshell-helper appearance-export SHARED_FILE`
  reads a bounded JSON snapshot from stdin, validates it and atomically writes
  shared mode 0640. It does not create the shared directory,
  change ownership, elevate privileges or start a service. The helper and QML
  must be deployed together for this protocol addition.

The desktop reports export failure through `nullshell ipc appearance status`.
Updates are coalesced; a failed export retries on the next colour/mode change or
desktop restart, not by periodic polling. Theme files persist after logout.
Greeter loads the latest result on startup and watches updates while running; it
never needs to run merely to receive an export. Without a running user session,
it retains the last exported mode, even across sunrise/sunset. This is intentional:
greeter does not run an independent scheduler or location client.


## Independent greeter wallpaper snapshots (version 1)

The greeter follows the **All displays** default wallpaper, resolved by
`WallpaperState.entryFor("")`. Per-output overrides are not exported and the greeter
does not guess which connected monitor to follow. Without a global default it
uses its theme background. Lock screens keep their existing per-output wallpaper
logic; this protocol only bridges the greeter account boundary.

`WallpaperExport.qml` watches the global selection/fit and the selected source
file for changes. It has its own coalesced exporter, independent of colour events.
The shared `wallpaper.json` contains exactly:

```json
{"version":1,"image":"wallpaper-0.img","revision":"1234-ab","fit":"cover"}
```

`image` is null, `wallpaper-0.img` or `wallpaper-1.img`, never an original HOME
path, arbitrary URL or directory traversal. Revision changes when image bytes
change so a reader can refresh even after missing intermediate events. Clearing
uses `image: null` and `revision: ""`. Fit is cover, contain or stretch.

The source file is **copied**, not linked. A published wallpaper therefore survives
logout, inaccessible HOME and source deletion; only the user exporter reads the
original location. PNG/JPEG/WebP raster signatures are accepted, with a **16 MiB**
source cap and regular-file requirement. This is a bounded format gate, not full
image validation; Qt decodes it and rendering failure falls back to the theme
background. A missing/unsupported/oversized new source preserves the previous
published wallpaper and reports an error via `nullshell ipc wallpaper status`.

The exporter compares bytes with the current asset. A fit-only change rewrites
only the descriptor, not the image. Changed images alternate between two fixed
asset slots. It writes the inactive asset first and atomically publishes the new
descriptor afterward. Steady-state asset use is at most **32 MiB**, with at most
one additional 16 MiB pending file during an interrupted write. No timestamped
archive or growing cache is created. The next successful export replaces the
fixed pending file. Clearing publishes null first, then removes both managed
slots; unrelated files and original images are never removed. Separate advisory
locks serialize each domain's writers without a daemon.

Portable setup additionally supplies `NULLSHELL_WALLPAPER_EXPORT_FILE` to the
source user's session and `NULLSHELL_WALLPAPER_FILE` to greeter. The NixOS module
sets both from the same configured directory. The ordinary-user command is
`nullshell-helper wallpaper-export SHARED_FILE`, accepting
`{"version":1,"source":"/absolute/local/image.png","fit":"cover"}` on stdin.
An empty source clears the published wallpaper. No shared directory is created
by the helper. Descriptors and images are 0640 even under umask 077.

Appearance, wallpaper and executable greeter QML are three different domains:

| Domain | Trigger | Published content |
| --- | --- | --- |
| Appearance | Mode or colour change | Small mode/colour snapshot |
| Wallpaper | Global selection, source-file or fit change | Small descriptor; image bytes only when changed |
| Greeter QML | Explicit software deployment | Packaged code; never selected by theme data |

Each reader starts from its latest persisted snapshot and subscribes to file
changes. Failure in one domain does not reset the other or the authentication
conversation. Disabling integration or moving its directory does not recursively
delete old administrator-configured locations; their removal is an explicit
installation cleanup, separate from the bounded runtime resource policy.


Greeter **code** selection is independent of both data domains. The NixOS option
`programs.nullshell.greeter.interfaceDirectory` supplies a root-managed optional
QML override location. With no installation the packaged QML is used. See
[DEVELOPMENT.md](DEVELOPMENT.md#local-greeter-qml-installation) for explicit
install/reset commands. Theme data cannot select executable QML.

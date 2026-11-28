# Configuration v1 (initial slice)

The desktop reads `$XDG_CONFIG_HOME/nullshell/config.json`, falling back to
`~/.config/nullshell/config.json`. It never writes this file. Maintain it by hand
or from dotfiles; Nix is not required. Greeter does not load this user config.

Optional Hyprland display profiles use a separate local file. See
[Display profiles](DISPLAYS.md) for output discovery, the schema and IPC.

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

Open **Idle and lock settings** from launcher search or the power panel to
edit the three timers in minutes:seconds (for example, `2:30`). **Save timers** stores a validated override in
`$XDG_STATE_HOME/nullshell/idle-policy.json`; it never edits `config.json`.
**Restore defaults** clears that override and follows the current configuration.
The page can pause or resume these timers with Keep awake. It does not configure
system suspend, the physical power button, or lid behaviour.

The configuration is watched and valid changes apply live. Changing idle
thresholds changes native idle monitors and may cause idle actions based on the
current session inactivity; this is not a guarantee of a fresh grace period.
Idle monitoring waits for both configuration and persisted Keep awake loading.
Invalid updates retain the last valid snapshot and emit an error for the shell
notification UI. Invalid configuration at first startup uses package defaults.
Missing files at first startup are normal. Removing a previously loaded file
retains that process's snapshot; use `{"version":1}` to reset explicitly.

The authoritative parser/defaults are `ConfigRules.js`; `ShellConfig.qml`
owns file loading and publication. Pages do not read files. Configuration covers terminal, idle, search aliases, notification history and appearance scheduling. Wallpaper and
greeter configuration remain separate settings domains. Legacy state migration is documented in
[DEPLOYMENT.md](DEPLOYMENT.md).

The greeter stores only the last successfully authenticated user and session ID
in its dedicated account's state file. On NixOS this is
`/var/lib/nullshell-greeter/last-login.json` (directory mode 0700, file mode 0600).
Other distributions can set `NULLSHELL_GREETER_STATE_FILE` to a writable path owned
by the greeter account. Missing or invalid state falls back to an empty user and
the available session list. Passwords are never stored, and the greeter does not
read a desktop user's home directory.

## Search aliases and notification policy

The empty command-panel state is unchanged. Exact names and literal keywords
rank before conservative name abbreviations (ASCII subsequences and initials,
such as `ff` for Firefox or `vsc` for Visual Studio Code). Comments are never
matched fuzzily. This is abbreviation matching, not spelling correction.
Existing command keywords include Chinese. Add personal aliases without editing
the command catalog or desktop entries:

```json
{
  "version": 1,
  "search": {
    "aliases": {
      "app:firefox": ["火狐", "浏览器"],
      "action:audio": ["声音设置"]
    }
  },
  "notifications": {
    "persistHistory": true,
    "historyDays": 7,
    "recordTransient": false,
    "excludedApplications": []
  }
}
```

Alias targets are `app:DESKTOP_ID` (with or without `.desktop`) or
`action:COMMAND_ID`. Aliases only affect matching, never execute commands or
create entries. At most 128 targets, 16 aliases per target and 128 characters per
alias are accepted. Prefix scopes and panel/action filtering remain unchanged.

Notification history stays bounded to 50 entries and pending notifications to
20. `historyDays` accepts 1–365 days (default 7); expired entries are removed on
load, policy changes and a one-minute maintenance tick. `recordTransient` defaults
to false, so transient hints appear without entering the center or disk history.
Older saved records lacking a transient flag cannot be retroactively classified.
`excludedApplications` matches exact desktop-entry IDs or app names, ignoring
case; excluded notifications still show banners, but are not recorded. It accepts
up to 128 names of 256 characters each.

`persistHistory: false` retains current-session history in memory, clears the
valid saved snapshot and stops writing notification contents. It does not import
previous disk history. Invalid saved files are preserved for explicit repair;
policy changes never overwrite an unreadable or unsupported snapshot. These
preferences are configuration, not writable UI overrides.

Search for **Pause notifications for one hour** / `勿扰`, or use **Quiet · 1h**
inside the existing notification details. Critical alerts, including critical
battery warnings, still appear. Ordinary notifications remain in the center;
resume never replays accumulated banners. **Resume notifications** ends the
period early. The desktop alone writes its expiry atomically to
`$XDG_STATE_HOME/nullshell/notification-quiet.json`; restart preserves an unexpired
period. This state does not override history policy. Invalid state uses an
inactive in-memory default and is preserved; read/write errors appear in the
details control's tooltip. Nothing is added to the homepage or idle desktop.

Application search dispatches through short-lived `systemd-run` clients into
independent user services in `app.slice`. `Type=exec` reports execution failures;
`ExitType=cgroup` keeps forked descendants owned by the application unit. The
client does not wait for application exit. Session display, input-method, PATH
and XDG context are passed by environment variable name, without values in argv.
No shell evaluates desktop-entry arguments. Up to eight dispatches can be pending;
manager startup has a ten-second deadline. Client timeout/failure is reported as
a local notification. Accepted dispatch does not guarantee a mapped window.

## Appearance snapshots (version 1)

The desktop owns the effective light/dark choice, persisted in
`$XDG_STATE_HOME/nullshell/appearance-mode` (existing choices are retained; a fresh
installation defaults to dark). The appearance button and light/dark actions
change this choice; optional automatic scheduling is described below.
The native nullshell Settings portal backend publishes the saved choice to
applications through the standard portal. There is no GSettings writer;
applications bypassing this portal are outside this publication contract.
Compositor application errors are exposed by `nullshell ipc call appearance status`.

The desktop exports its actual
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
  # appearance.enable = true; # default
  # appearance.directory = "/var/lib/nullshell-appearance";
};
```

No username needs to be configured. When `greeter.appearance.enable` is true (the
default when `greeter.enable = true`), the system provisions a `0711 root:root`
container at `/var/lib/nullshell-appearance/users` and a `2750 <user>:greeter`
slot directory for each ordinary local account (`1000 <= uid < 60000`) via
`nullshell-appearance-slots.service` and a `user@.service` `ExecStartPre` hook.
Each user can replace only their own slot's theme/wallpaper data; `greeter` has
read-only group access (`0640`), and other ordinary users cannot list or read peer
slots. No user's `HOME` is exposed to `greeter`, and no personal name or path is
embedded in QML or system configuration.

Portable installations (e.g. Arch Linux) use the exact same systemd and tmpfiles
units via `make install-greeter-system`:

- `tmpfiles.d/nullshell-greeter.conf` creates `/var/lib/nullshell-greeter` (`0700`),
  `/var/cache/nullshell-greeter` (`0700`) and `/var/lib/nullshell-appearance/users`
  (`0711 root:root`).
- `nullshell-appearance-slots.service` and `user@.service.d/nullshell-appearance.conf`
  invoke `nullshell-helper ensure-appearance-slot` (`--local` before `greetd` and
  `%i` before user session startup) to maintain `2750 <user>:greeter` per-user slots
  using `openat` + `O_NOFOLLOW` without a resident root daemon.
- The desktop automatically exports to `/var/lib/nullshell-appearance/users/$USER/`
  when that slot exists (`--optional` skips silently on hosts without a greeter).
  `NULLSHELL_APPEARANCE_DIR` relocates the slot root (`"off"` disables export), and
  `NULLSHELL_APPEARANCE_EXPORT_FILE` / `NULLSHELL_APPEARANCE_FILE` remain available
  for isolated previews and single-file overrides.
- Greeter follows the `rememberedUser` from `last-login.json` on startup and updates
  dynamically when a different username is entered in the login field.

The desktop reports export failure through `nullshell ipc appearance status`.
Updates are coalesced; a failed export retries on the next colour/mode change or
desktop restart, not by periodic polling. Theme files persist after logout.
Greeter loads the latest result on startup and watches updates while running; it
never needs to run merely to receive an export. Without a running user session,
it retains the last exported mode. Greeter does not run a scheduler or location client.


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

Portable and NixOS setups share the same `/var/lib/nullshell-appearance/users/<user>/wallpaper.json`
slot convention alongside `theme.json` (`NULLSHELL_WALLPAPER_EXPORT_FILE` and
`NULLSHELL_WALLPAPER_FILE` remain available as explicit single-file overrides).
The ordinary-user command is `nullshell-helper wallpaper-export [--optional] SHARED_FILE`, accepting
`{"version":1,"source":"/absolute/local/image.png","fit":"cover"}` on stdin.
An empty source clears the published wallpaper. No shared directory is created
by the exporter. Descriptors and images are 0640 even under umask 077.

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

## Automatic appearance and optional Settings backend

The desktop owns the effective light/dark mode. To calculate sunrise/sunset
locally without a location service, add this to `config.json` (coordinates below
are an example, not package defaults):

```json
{"version":1,"appearance":{"mode":"solar","location":"fixed","latitude":0,"longitude":0}}
```

`appearance.mode` defaults to `manual`; `solar` enables automatic decisions.
`location` defaults to `timezone`, which estimates position from the named system
time zone and local `tzdata`. For `fixed`, supply numeric latitude (-90..90) and
longitude (-180..180). Without a usable location the current theme is retained.
Use `"location":"ip"` to opt in to looking up your public IP via BeaconDB.
Coordinates are rounded to 0.1° and kept only in memory. Requests run on entry
and every 30 minutes; failed refreshes retry after five minutes and retain the
last available coordinates. VPNs and proxies can affect accuracy. An old
`"location":"geoclue"` value is treated as `"timezone"`, not consent to an IP lookup.

The helper calculates solar altitude locally using NOAA equations and a -0.833°
horizon. This is an approximate sunrise/sunset schedule (not a weather or terrain
model), supported for 2000–2099. The desktop refreshes it every minute, detects
clock jumps on a 30-second tick, and recalculates after resume. Switching may lag
the calculated boundary by up to about one minute. Polar day/night has no next
transition within the two-day search window and is re-evaluated normally.

The Appearance page offers persistent Light/Dark/Automatic selection and
location controls; UI preferences live in `appearance-policy.json` and override
this configuration until **Use configuration defaults** is selected.
The existing quick light/dark actions in solar mode override until the next known transition,
or for 24 hours if none is known. The expiry survives desktop restart in
`$XDG_STATE_HOME/nullshell/appearance-override.json`; `appearance-mode` remains
the effective mode consumed by lock/Polkit/portal. To end the override early:

```sh
nullshell ipc call appearance resumeAutomatic
nullshell ipc call appearance status
```

Status includes `automatic`, `nextTransition` (UTC Unix seconds or null),
`overrideUntil`, and errors. Changing configuration does not erase a manual
override; resume explicitly when desired. Setting mode back to `manual` disables
location and solar subprocesses. Greeter still reads only the exported snapshot.

The optional native Settings portal backend publishes `color-scheme` through
`org.freedesktop.impl.portal.Settings`: Read, ReadAll, SettingChanged and version 1.
It is a separately D-Bus-activated helper process, not a general-purpose daemon.
It reads the effective mode file once per second, emits only changes, returns
no preference (0) before a valid initial value, and retains its last valid value
across malformed/missing files. It has no write method and never changes user
configuration. No parallel GSettings publication is performed.
Other Settings keys can come from a fallback backend such as GTK.

See [APPEARANCE.md](APPEARANCE.md) for portable installation and Nix integration.

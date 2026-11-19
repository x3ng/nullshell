# Development, acceptance and deployment

Nix supplies reproducible dependencies and deployable snapshots. It is not the
UI edit loop. Source commits, releases and host activation are separate actions.

## Current working entries

Run from the source checkout with installed dependencies:

```sh
./bin/nullshell preview-connectivity
```

Or obtain the development environment without publishing anything:

```sh
nix develop --command ./bin/nullshell preview-connectivity
```

Quickshell loads the working QML files and reloads on edits. The connectivity
preview uses the production component with synthetic states. It does not change
radios or start a second notification/idle/lock service. Resize it and inspect
connected, disconnected, disabled, unavailable and multiple-device states in
both palettes. Keep screenshots and logs outside the repository.

The login and Polkit preview commands also exist. Their offscreen checks prove
loading and process survival, not actual window presentation or visual quality.
Confirm a real window is mapped and inspect its screenshot before claiming success.

## Full command-panel preview

The power button opens the session page. In the preview, lock, sleep, logout,
restart and shutdown change only the synthetic `lastAction`; no session command
or capability probe is instantiated. Use `preview page session`, or activate
`power-menu-button`. `preview sessionState error|busy|unavailable|normal` selects
feedback states. Destructive choices require `power-confirm`; `power-cancel` and
leaving the page clear the pending choice. The physical power key is unchanged.

```sh
./bin/nullshell preview-panel
# Or: nix develop --command ./bin/nullshell preview-panel
```

This entry uses the actual LauncherPanel on the Wayland compositor with synthetic
PanelFixture state, an independent `nullshell-preview-panel` namespace and IPC.
It starts no desktop service, notification owner, idle inhibitor or authentication
agent. The fixed clock, tray, search, media, network and workspace fixtures are
injected; actions only alter memory or record their intent. It captures keyboard
focus while open, like the real panel. Escape or outside-click hides it; Ctrl+C
terminates the foreground process. It is a development fixture, not a security
sandbox for arbitrary QML.

In a second terminal at the same checkout, control the running preview:

```sh
preview() { quickshell ipc -p "$PWD/preview-panel.qml" call preview "$@"; }
preview openPanel
preview scenario crowded     # normal, empty, crowded, media
preview width 440            # default 740; narrow layout and workspace wrapping
preview light true
preview blur false          # simulate opaque fallback; true simulates blur support
preview page bluetooth       # overview, desktop, wifi, bluetooth, audio, media, notifications, appearance
preview search terminal
preview tick                 # change window titles without changing identities
preview status
preview close
preview quit
```

Save QML to reload, without a build or deployment. An invalid edit may leave the
last successful scene visible; inspect the reload log, correct it and verify a
fresh start before acceptance. No real app launch, device connection, session
lock or shutdown occurs from preview controls. Native tray menu protocol and
real hardware behavior need integration testing separately.

Use `grim /tmp/nullshell-panel.png` after the frame/resize has settled, then inspect
the image. The portable `tests/test_panel_preview.py` cycles scenarios and pages, checks
settled geometry and optionally writes screenshots. The desktop VM invokes the
same script and separately checks native layer mapping and production process
isolation. The
same VM confirms that greeter/lock/Polkit preview windows really map.

The full panel currently requires a Wayland compositor; it is not a freely
resizable ordinary window or an offscreen-only renderer. The IPC width control
covers layout resizing. Material tests use `preview blur` to inject capability results, never to modify
the host compositor. Run `python3 tests/test_surface_capabilities.py` for the
read-only Hyprland probe failure/timeout cases without a graphical session.
Native blur requires compositor protocol support; keep
software-rendered VM screenshots distinct from physical GPU visual acceptance.

Acceptance covers the default panel, search and details; short/long labels;
zero/many windows, notifications and devices; media absent/present; both palettes
and constrained widths. Exercise keyboard/hover and changing titles, not only
static screenshots. Test authentication and real backend behavior in VMs.

## Checkpoints and releases

1. Edit local source and inspect the relevant live preview. No commit, tag,
   network push, flake update or Home Manager activation is needed to view edits.
2. Iterate until the intended layout and interactions are accepted. Keep trial
   changes local; make coherent commits at useful checkpoints, not per adjustment.
3. Run checks appropriate to the change. Use integration VMs for protocol,
   authentication and service changes, not as a substitute for visual review.
4. Publish a release only at an agreed milestone. Record evidence and remaining
   limitations; never label an unreviewed layout a validated release.
5. Only then update consumer lockfiles and activate the accepted deployment.

Preview work must not require rebuilding Rust. Rebuild the helper only when its
source or protocol changes; test it on private buses/VMs before real integration.

## Editable desktop checkout

Clone this repository to `$XDG_CONFIG_HOME/quickshell/nullshell`. The root
`shell.qml` is a native Quickshell configuration entry. The runtime package
provides dependencies/helper and the `nullshell` launcher without QML assets.
It resolves this checkout for both direct startup and IPC. `quickshell -c nullshell`
also works with dependencies on PATH, but must not run beside an existing desktop process.

Desktop QML is watched by Quickshell. Work with isolated previews first: a live
reload recreates notification/idle objects, even though persisted state survives.
The locker and Polkit agent disable watching and must not be restarted to preview
an edit. Inspect their dedicated previews; apply accepted changes on next login.
The system greeter uses the independently deployed package snapshot.

Personal Hyprland and application configuration remains in the separate dotfiles
repository, deployed with its own tools. No Home Manager ownership or
out-of-store symlink is required for the nullshell checkout.

## Read-only login information preview

Lock and greeter share the battery/charging, keyboard-layout and Caps Lock
presentation in `LoginView`. `adapters/LoginInfo.qml` reads UPower natively.
On Hyprland, it queries `hyprctl -j devices` when locking/focusing the form,
changing layouts or releasing Caps Lock. Queries are bounded, read-only and
disabled when the locker is idle; there is no periodic polling or helper change.
Absent or ambiguous keyboard data is hidden. In particular, the cage greeter
does not inherit Hyprland keyboard state. No authentication or power policy is
changed by these status fields.

`preview.qml` uses synthetic status values, never the production information
adapter. Run the shared-view regression in a private compositor with:

```sh
nix develop --command python3 tests/run_panel_headless.py --login-info --keyboard --screenshots /tmp/nullshell-login-info
```

The preview IPC accepts `info normal|low|full|missing|long|cage`, `mode true|false`
(lock/greeter), `light true|false` and `size WIDTH HEIGHT`. Size pins the preview
window constraints for reproducible screenshots. This checks presentation and
input event forwarding, not PAM or session-lock safety. Live locker processes
do not reload; apply on their next normal launch. The system greeter consumes
its installed snapshot, which must be explicitly updated separately.

## Local greeter QML installation

The package remains the default code source. On NixOS, enabling the greeter also
installs `nullshell-install-greeter` and configures
`programs.nullshell.greeter.interfaceDirectory` (default
`/var/lib/nullshell-greeter-ui`). This is separate from mutable theme data and
from the greeter account's login state. Deploy this module/runtime support once;
subsequent QML edits do not require a flake update or host switch.

After inspecting the working-tree preview, install the current checkout:

```sh
sudo nullshell-install-greeter --source "$PWD"
# Equivalent convenience target from this checkout:
make install-greeter
```

The installed command already knows the directory chosen by the system module.
It does not infer a username, HOME or checkout location. A portable installation
can invoke `sudo ./bin/nullshell-install-greeter --source "$PWD" --destination DIR`
and set `NULLSHELL_GREETER_OVERRIDE_DIR=DIR` for the greeter launcher. Install its
normal packaged resources/dependencies first with Make and the distribution's
greetd configuration. The command requires coreutils, findutils and util-linux;
there is no runtime Python or Nix dependency. The destination parent must already
exist and be root-managed.

The command **copies**, never moves, QML/JS and their source resource directories
(`components`, `adapters`, `greeter`, optional `assets`) into a root-owned snapshot.
It includes the package's static `wallpaper.json` if present. It does not copy Git,
backend binaries, desktop HOME config or runtime state. Extra static images/fonts
belong in `assets/`. Device files and links escaping the installed snapshot are rejected; internal
shared-component symlinks are preserved. Files become 0644 and
directories 0755. A `greeter-interface.version` marker must match resource interface
version 1, and the snapshot's allocated size must not exceed 64 MiB.

This is structure/version validation, **not execution of user QML as root**, and
not a proof of QML syntax, runtime module availability or successful login. Preview
with the intended runtime before installing. An API marker does not certify every
arbitrary Qt/Quickshell import a custom interface may add.

A complete snapshot is published by atomically changing `current`. Greeter code
watching is disabled; theme/wallpaper data watching remains enabled. A running
greeter pins its selected snapshot with a shared file lock, so resource cleanup
cannot remove images/imports it may still need. Unused snapshots are collected on
install/reset. There is no automatic rollback or version-history archive; at most
four selected/in-use snapshots may exist, and another installation refuses if
that limit is reached. An interrupted installation is cleaned on the next command.

Installation never restarts greetd, the locker or Polkit. The next greeter launch
uses the installed interface. If needed, repair from another working TTY and
restart greetd only when no authentication or graphical session must be preserved.
TTY recovery is an operating-system prerequisite, not guaranteed by this installer.
An invalid installed interface is reported rather than silently replaced.

To explicitly return to the package on the next launch:

```sh
sudo nullshell-install-greeter --reset
```

This removes the override selection and collects unused copies, without touching
appearance data or login state. The greeter entry remains `greeter.qml` at the
resource root and loads `greeter/shell.qml`; the complete snapshot is needed for
shared components. Lock and Polkit entries are not changed by this installation.

### Isolated appearance/panel interaction tests

`nix develop --command python3 tests/run_panel_headless.py --screenshots /tmp/panel-review --keyboard`
starts a private labwc headless compositor using pixman, with software OpenGL
for Qt Quick so rounded clipping uses the actual rendering path. It does not use host
input or capture host windows. This complements the Hyprland VM and permits
interaction/visual checks without KVM. The screenshot helper captures the actual
panel card; inspect both palettes and narrow/wide appearance states before release.

### Quick controls interaction contract

The empty-query home page is Quick controls. Radio icons perform
one immediate action; their separate labelled rows and arrows open detail pages.
Radio icons use the same neutral treatment as the other home controls. Connection
names and secondary status share one compact row; off/busy/error states replace
the connection text. Toggle accessibility reports whether the radio is enabled.
A busy or unavailable control cannot toggle, while its details remain reachable. Volume's icon toggles mute;
its arrow opens audio devices. Brightness's arrow opens appearance settings;
the slider continues to adjust backlight. Search keeps explicit action names separate from
settings-page names.

Appearance settings and explicit light/dark/resume actions remain searchable;
appearance does not occupy a home-page row. Power opens a menu containing lock,
and destructive session actions retain confirmation. The footer packs workspace,
tray and awake/power controls into centered rows, with consistent gaps within and
between groups. Each wrapped row is centered independently. Keyboard focus exposes the
same tooltips as hover. Escape returns from details/search to home before closing.

The headless preview regression covers split targets, appearance settings,
disabled/busy actions, both palettes and narrow/wide home layouts, in addition to
the existing detail, search and session-menu checks. Preview actions remain fake.

The overview scrolls keyboard-focused controls into view, including wrapped tray
and session controls. Tray items support Enter/Space to activate and Menu or
Shift+F10 to open their menu. Native menus support Up/Down, Enter/Space, Right to
enter a submenu and Left/Escape to leave it. Disabled entries and separators are
skipped. Preview checks exercise focus visibility and synthetic tray activation;
native DBusMenu population still needs integration acceptance.

The notification header's bell button and corresponding searchable
commands pause ordinary banners for one hour without adding homepage content.
The slashed bell indicates paused banners. Pending and History switch views.
Critical alerts remain visible. Search aliases and disk-history policy are
documented in [CONFIGURATION.md](CONFIGURATION.md).

### Visual geometry conventions

Evaluate the complete visible region, including parent gaps, child padding and
control height. Equal outer margins alone do not produce equal visual bands.
The home/search header and single-row footer use `Theme.stripHeight`; workspace
wrapping adds rows without changing the edge insets or horizontal centering.

The parent owns spacing between sections; children own spacing inside a control.
Avoid adding the same edge inset at both levels. Detail content uses the full
header width, with its scrollbar inside the outer panel inset. Detached detail
windows use the same `panelPadding` as embedded pages.

Detail pages use the implicit heights of their shared controls: 32 px for
compact header buttons, 36 px for standard actions and 40 px for text fields.
Match the height of native controls placed alongside them. Use a check mark
for an active player and a chevron for navigation. `Layout.fillWidth` alone does not make
buttons equal-width: use equal preferred widths for paired actions. In vertical
command lists, align icon and text columns independently of label length; retain
centered content for standalone and paired buttons.

Qt layouts can compute `implicitHeight` from their children even when a larger
preferred/minimum height is specified. Content-fit calculations must use the same
height constraint as the layout, or otherwise-fitting pages gain a scroll range.
Check actual rendered light/dark, narrow/wide, short/long and wrapped states;
font metrics and icon optical weight still need visual judgment. Authentication
views are reviewed through their previews, never by restarting live agents.

### Detachable settings

Wi-Fi, Bluetooth, audio, media, notifications, appearance and wallpaper open inside
the command panel by default. Their header's window button moves the existing
page into an ordinary resizable window and dismisses the launcher. Ctrl+Shift+D
also detaches the current detail page;
the shortcut is disabled in detached windows, power confirmation and file dialogs.
Input drafts and selections survive this move. Clicking outside the ordinary window does not
close it. Opening the same feature again focuses its existing window; closing it
discards unsubmitted drafts and the next invocation opens inside the panel again.
Escape or the header's close button closes a detached window. Power/session
confirmation, home and search remain inside the panel. Windows are not restored
across process restarts.

Wallpaper uses the same detail header and stays open after applying an image.
Its preview keeps a 16:9 frame as the page width changes. The panel fits the
content up to the shared screen/height cap, then scrolls the detail body instead
of compressing controls or the image. Detail pages expose a scrollbar and scroll
keyboard-focused controls into view. Detached windows initially fit their content
under the same height cap; subsequent user resizing keeps the body scrollable.
Its standard file chooser temporarily releases the launcher's layer/focus so
the dialog can be used, then restores the panel on acceptance or cancellation.
Service activity follows both the launcher and detached pages; closing the
launcher alone must not stop discovery in a detached Wi-Fi page. Bluetooth page
cleanup must not be triggered by another page closing.

The panel preview exposes `closeDetached SECTION`, `resizeDetached SECTION WIDTH
HEIGHT`, and `captureDetached SECTION PATH`; `status` includes detached sections.
The headless regression checks preserved drafts, multiple independent windows,
repeat navigation, close/reopen behavior, and palette/width screenshots. Its
device operations remain synthetic, not hardware integration certification.
The private compositor keeps a virtual keyboard attached for focus/shortcut
checks. Full-desktop captures are enabled only by that isolated runner; ordinary
preview captures remain limited to their own view.

### Command browsing

A bare `>` lists the command catalog. `>?` browses panels and `>!` selects actions;
keywords follow the prefix, with or without a space. The search field shows the
other command scopes as clickable hints on its right. Clicking a hint replaces
only the prefix, preserves keywords and returns typing focus to search. There is
no separate filter row or hidden filter state: deleting `?` or `!` returns to all
commands, and reopening the panel starts with the usual empty query.

Each command carries an explicit panel/operation classification from ShellActions.
Search rows show Panel or Action, with Open or Run hints on the selected result;
unavailable results cannot execute. The power/session command opens its menu,
where destructive actions retain confirmation. No new direct power action is
introduced by filtering. Preview command entries are synthetic and execute no
system operations.

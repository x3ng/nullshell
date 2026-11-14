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
preview page bluetooth       # overview, desktop, wifi, bluetooth, audio, notifications
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

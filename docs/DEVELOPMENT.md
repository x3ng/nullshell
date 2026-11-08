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
same script and separately checks native layer mapping and production service
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
It resolves this checkout for both services and IPC. `quickshell -c nullshell`
also works with dependencies on PATH, but must not run beside the desktop service.

Desktop QML is watched by Quickshell. Work with isolated previews first: a live
reload recreates notification/idle objects, even though persisted state survives.
The locker and Polkit agent disable watching and must not be restarted to preview
an edit. Inspect their dedicated previews; apply accepted changes on next login.
The system greeter uses the independently deployed package snapshot.

Personal Hyprland and application configuration remains in the separate dotfiles
repository, deployed with its own tools. No Home Manager ownership or
out-of-store symlink is required for the nullshell checkout.

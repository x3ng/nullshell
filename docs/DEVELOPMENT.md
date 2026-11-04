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

## Full command-panel preview: required next work, not implemented

The connectivity preview cannot validate the overall panel. Before further panel
layout iteration, add an isolated entry that reuses the actual LauncherPanel with
fixtures. Inject tray items, time and target screen instead of hard-binding them
inside presentation code. Use a separate namespace and preview IPC; closing it
must not affect production. Audit the entire child tree for direct service calls
and persistent state before calling it isolated.

This first entry can use the actual layer window on the compositor, allowing
inspection of panel layout and native blur without a second desktop service.
For freely resizable window previews, subsequently extract shared panel content
into an ordinary QML Item used by the production layer window and a FloatingWindow.
Do not duplicate the panel UI or require that larger refactor just to start the
first preview. Keep compositor focus and native blur in the layer wrapper.

The preview must provide deterministic services, controls, search results,
notifications, media, clock, workspaces and tray fixtures. Actions should update
mock state or record intent, never launch programs, switch workspaces, suspend,
authenticate, write real preferences or change device connections. Do not import
the full desktop entry as a preview: it starts real service owners. Do not start
a second production shell alongside the existing desktop.

Acceptance must cover the default panel, search and detail pages; short/long
labels; zero/many windows, notifications and devices; media absent/present;
light/dark palettes; normal and constrained sizes; keyboard focus and hover.
Inspect screenshots after changes, and exercise state changes without flicker.
Use a separate layer-window preview with the same fixtures on a nested
compositor or in the Hyprland VM to check blur, mapping and compositor behavior.
A normal window screenshot alone cannot establish those effects.

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

## Personal dotfiles

Personal configuration belongs in the independent dotfiles repository. A local
development deployment links application configuration to that checkout, using
ordinary symlinks on other distributions or mkOutOfStoreSymlink with Home Manager.
Once links are established, editing existing config files only requires the
application's reload behavior, not a new commit, input update or switch.

Changing packages, service definitions, the set of managed paths or deployment
modules may need a new activation. Immutable release profiles deliberately use
pinned snapshots and are a separate deployment choice, not the daily edit loop.
Before enabling local links, reconcile the checkout with the migrated config
layout and verify every target and autostart entry. A development profile whose
targets do not exist is not a working development environment.

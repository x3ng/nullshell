# Appearance implementation and distribution integration

Core functionality is independent of Nix:

- `AppearanceSchedule.qml`: automatic/manual policy and override persistence.
- `adapters/SolarProvider.qml`: bounded helper invocations and result validation.
- `backend/src/solar.rs`: pure UTC solar calculation, no network or D-Bus.
- `backend/src/location.rs`: optional GeoClue client; city accuracy, explicit
  deletion after success/error/timeout. Dropping its connection releases ownership.
- `backend/src/settings_portal.rs`: read-only Settings protocol and mode-file reader.
- `AppearanceState.qml`: sole writer of effective mode; existing compositor,
  portal and greeter exporters consume the result.

No QML page owns a service lifetime. No helper parses Nix, infers a personal
account, or configures the compositor. The independent portal process can start
before/after the desktop and remains available when a page or desktop is closed.
It is enabled only by explicit distribution/session integration.

## Portable installation

`make install PREFIX=/usr DESTDIR=...` builds with Cargo and installs the helper,
a portal descriptor, D-Bus activation file and GeoClue desktop identity.
It neither enables services nor modifies user settings. Build/install dependencies
remain in [BUILDING.md](BUILDING.md); no Nix evaluation is needed.

For a session using this backend, configure the existing xdg-desktop-portal
installation using its session-specific `*-portals.conf` or `portals.conf`:

```ini
[preferred]
org.freedesktop.impl.portal.Settings=nullshell;gtk;
```

Keep existing defaults for file pickers, screenshots and other portal interfaces.
The prefix's `share` directory must be in XDG_DATA_DIRS / D-Bus service discovery.
D-Bus activates `nullshell-helper settings-portal` from the installed absolute
path. Plan routing changes for the next login; installation is not authorization
to restart a running desktop portal.

GeoClue is optional. Fixed coordinates require no location package, agent or
network. For automatic location, install/configure GeoClue and its desktop agent
according to the distribution. The desktop identity is `org.nullshell.desktop`
(file `org.nullshell.desktop.desktop`); permit that client in GeoClue policy.
Do not embed personal coordinates or credentials in package defaults.

## NixOS

```nix
programs.nullshell = {
  enable = true;
  appearance.portal.enable = true;
  # Optional: requires usable GeoClue providers on this machine.
  appearance.geoclue.enable = true;
};
```

The module installs/declares the backend and routes Hyprland's Settings interface.
It does not configure solar policy or coordinates; those belong to the same user
JSON used on every distribution. Existing explicit Settings routes should be
removed to avoid merged competing preference lists. A GTK fallback must be
installed separately if other GTK Settings keys are wanted. Other compositors
can use the same portable descriptor with their own session routing.

`nix/packages.nix` owns dependency paths and activation-file substitution;
`nix/nixos.nix` owns service/GeoClue integration. QML and helper derivations remain
independent. The default package installs the complete runtime without user QML.
The NixOS module explicitly enables optional location and portal integration.

## Validation

`cargo test --manifest-path backend/Cargo.toml` covers solar boundaries, polar
seasons, invalid inputs and namespace matching. `make check-settings` requires
Python dbus-next and dbus-run-session for tests only; it starts a private bus and
synthetic GeoClue service, including denial, malformed data and timeout cleanup.
The Nix settings check also launches the real portal frontend on that private
bus to test descriptor discovery, activation and forwarded signals. `make check-appearance` also exercises real offscreen
QML with isolated state, including manual override restart/resume and location
failure. Use `nix develop` for the provided test tools.

The heavier `legacyPackages.<system>.tests.desktop-vm` checks the actual portal
frontend/backend routing in a disposable Hyprland session. Private-bus and
mock-location tests do not prove physical-machine location coverage. No visual
layout changed; these checks are protocol/application tests, not visual acceptance.

## Appearance controls

Open the overview's sun/moon button, or search for **Appearance settings**.
The detail page offers **Light**, **Dark**, and **Automatic**. Light/Dark here
select a persistent manual mode. Automatic follows sunrise/sunset and clears any
temporary override. With no configured fixed coordinates, choosing Automatic
selects device location; this is the explicit request to use optional GeoClue.
The location controls show progress/failure, allow retry, or accept fixed
latitude/longitude with validation. Fixed coordinates work without GeoClue.

The existing light/dark search commands and `appearance setMode` IPC remain
short-lived overrides when automatic mode is active. The page displays their
expiry and offers **Resume automatic**. `appearance selectMode auto|light|dark`
uses the same persistent selection as the buttons.

UI choices are stored in `$XDG_STATE_HOME/nullshell/appearance-policy.json`.
Only this declared appearance preference domain overrides user configuration;
`config.json` is never rewritten. **Use configuration defaults** clears the UI
override and resumes the configured policy. Effective mode and temporary override
expiry remain in their existing independent state files.

`tests/run_panel_headless.py --screenshots /tmp/panel-review --keyboard` exercises
the actual production controls with synthetic state on a private labwc compositor.
No host keyboard, desktop state or service is used. Optional screenshots require
Python Pillow (test dependency only) and reject an unrendered content region. Captures contain only the
preview card. `checks.<system>.panel` runs this reproducibly with Nix and saves
rendered screenshots in the derivation output. Inspect those images in addition
to the interaction assertions; compilation alone is not visual acceptance.

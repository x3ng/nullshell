# Appearance implementation and distribution integration

Core functionality is independent of Nix:

- `AppearanceSchedule.qml`: automatic/manual policy and override persistence.
- `adapters/SolarProvider.qml` and `adapters/SolarMath.js`: in-process UTC NOAA
  solar calculation plus bounded helper coordinate lookups.
- `backend/src/timezone.rs`: resolves the local time zone and looks up its
  representative coordinates in the installed IANA `zone.tab`, offline.
- `backend/src/location.rs`: opt-in HTTPS IP lookup via BeaconDB (an empty
  Ichnaea request), with a short timeout and coordinates rounded to 0.1°.
- `backend/src/settings_portal.rs`: read-only Settings protocol watching the
  mode file via `inotify` without background polling.
- `AppearanceState.qml`: sole writer of effective mode; existing compositor,
  portal and greeter exporters consume the result.

No QML page owns a service lifetime. No helper parses Nix, infers a personal
account, or configures the compositor. The independent portal process can start
before/after the desktop and remains available when a page or desktop is closed.
It is enabled only by explicit distribution/session integration.

## Portable installation

`make install PREFIX=/usr DESTDIR=...` builds with Cargo and installs the helper,
a portal descriptor and its D-Bus activation file.
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

Time-zone estimation uses the system `tzdata`; time zones such as UTC have no
representative city. IP lookup uses `curl` as the HTTPS transport. No location
daemon, agent, portal, or D-Bus connection is used for either. BeaconDB sees your
public IP, which may reflect a VPN or proxy exit. The request contains no Wi-Fi
or cell identifiers. Returned coordinates stay in memory. See [BeaconDB's
privacy notice](https://beacondb.net/privacy).

## NixOS

```nix
programs.nullshell = {
  enable = true;
  appearance.portal.enable = true;
};
```

The portal option installs the backend and routes Hyprland's Settings interface.
It does not configure solar policy or coordinates; those belong to the same user
JSON used on every distribution. Existing explicit Settings routes should be
removed to avoid merged competing preference lists. A GTK fallback must be
installed separately if other GTK Settings keys are wanted. Other compositors
can use the same portable descriptor with their own session routing.

`nix/packages.nix` owns dependency paths and activation-file substitution;
`nix/nixos.nix` owns optional Settings portal activation. QML and helper derivations remain
independent. The default package installs the complete runtime without user QML.
The runtime includes `curl`; IP location requires no NixOS option or service.

## Validation

`cargo test --manifest-path backend/Cargo.toml` covers coordinate/HTTP response
validation, bounded snapshot validation, deterministic display fingerprints and
namespace matching; `tests/config.qml` covers in-process solar boundaries and
polar seasons.
`make check-settings` requires Python dbus-next and dbus-run-session for tests
only; the Settings test does not exercise location.
The Nix settings check also launches the real portal frontend on that private
bus to test descriptor discovery, activation and forwarded signals. `make check-appearance` also exercises real offscreen
QML and Rust with isolated state, a timezone table and a synthetic HTTPS
response, including opt-in, offline mode, manual overrides, restart/resume
and lookup failure.
Use `nix develop` for the provided test tools.

The heavier `legacyPackages.<system>.tests.desktop-vm` checks the actual portal
frontend/backend routing in a disposable Hyprland session. The offline location
fixture does not measure BeaconDB availability or IP location accuracy.

## Appearance controls

Open the overview's sun/moon button, or search for **Appearance settings**.
The detail page offers **Light**, **Dark**, and **Automatic**. Light/Dark here
select a persistent manual mode. Automatic follows sunrise/sunset, using
**Time zone** by default. It rechecks the zone about once a minute. Choose
**Coordinates** if the representative city is too far away, or explicitly
choose **IP location** to fetch an estimate online. A failed refresh keeps the
last usable coordinates in memory; without coordinates the theme stays as-is.
A legacy GeoClue choice becomes **Time zone**, not an IP lookup. Remove any old
`programs.nullshell.appearance.geoclue.enable` setting when updating the NixOS module.

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

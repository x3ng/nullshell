# Visual system

Nullshell follows a restrained, flat Material-style hierarchy. Background,
panel, raised controls and selected controls use distinct tonal surfaces from
`qml/Theme.qml`. Elevation is a small shadow where a floating surface needs to
separate from its background. Cards have no simulated gloss or inner highlight.

The command panel is an on-demand status and search surface, so its overview
keeps workspace, connectivity, levels, notifications and active media visible
without becoming a permanent bar. The panel width is a shared theme token and
all routes use the same card width. Dense lists retain scrolling instead of
stretching the whole window.

The desktop panel, notifications, OSD, Polkit prompt and tray menu use a muted
translucent tint over a rounded `BackgroundEffect.blurRegion`. Hyprland 0.57 and
Quickshell 0.3.2 expose `ext_background_effect_manager_v1`; the compositor samples
only the requested card region, leaving the rest of the screen sharp. The tint's
opacity comes from one theme token. If another compositor lacks the protocol,
its integration should use opaque surfaces instead of showing unblurred contents
through the card.

The command panel leaves the surrounding desktop undimmed; its transparent
outside-click area only handles dismissal.

The glass surface and its blur region appear together; fading a whole surface
from transparent would leave the compositor's blur visible before the tint.
Page-content transitions can animate inside an already mapped surface.

The greeter uses a system-owned solid background and the same login card as the
locker. Cage does not provide the desktop blur protocol. The locker blurs its own
wallpaper and uses a darker, more opaque card to keep password entry legible.

The useful reference from Dux Modular Shell (formerly Dank Material Shell) is
its semantic surface roles and separation between presentation and system
services. See `quickshell/Common/Theme.qml` and
`quickshell/Modules/Lock/LockScreenBackground.qml` in
`https://github.com/duxlabs-dev/dux-shell` (reviewed at commit `9f39bde`).
No DMS source or visual assets are imported.

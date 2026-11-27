# Visual system

Nullshell follows a restrained, flat Material-style hierarchy. Background,
panel, raised controls and selected controls use distinct tonal surfaces from
`Theme.qml`. Elevation is a small shadow where a floating surface needs to
separate from its background. Cards have no simulated gloss or inner highlight.
Corners are small and decorative: 6px for the panel, 4px for cards, inputs and
controls, 3px for small marks; nested shapes never round more than their
container. Surfaces are cool neutral greys with restrained blue accents.

State is never carried by one colour alone. Hover lifts a surface; selection
keeps its own fill and survives hover; keyboard focus is a 2px ring drawn inside
the control, so it never moves layout. Unavailable items keep a readable label
and only dim their icon. Level fills (mixer streams) use their own colour rather
than the selection fill. Dividers are decorative; inputs use a stronger
`fieldOutline` so fields can be found. `tests/test_palette.py` checks text and
boundary contrast for both modes against these roles.

Rows on the home page share rails across cards: leading icon centre, label start
and chevron column line up between the status cards, the settings directory and
the notification row, at both two-column and single-column widths. The directory
uses a quieter fill than live controls. Glass tint stays at about 0.9 so wallpaper
detail never competes with text.

The command panel is an on-demand status and search surface, so its overview
keeps workspace, connectivity, levels, notifications and active media visible
without becoming a permanent bar. The panel width is a shared theme token and
all routes use the same card width. Dense lists retain scrolling instead of
stretching the whole window.

Keep search visibly a text field; any inline status is read-only and gives way
to input and search controls when typing. The overview
groups quick operations by domain and gives persistent preferences labelled
entry points; search reaches those same pages. Reuse the existing group surface
and navigation row instead of giving each preference its own tile style. Do not
add headings that simply repeat what the labels and icons already communicate.

Parents own spacing between sections; controls own their internal padding. Use
the same height constraints for content-fit calculations and actual layout, or
an otherwise-fitting page can acquire a false scroll range. Scroll focused
controls into view rather than shrinking interactive controls to fit.

Settings pages use a title and short description, shared section surfaces, and
one accent action for save or confirmation. Keep actions that must remain
reachable outside the scrolling form. Display confirmation shows the affected
outputs and changed fields separately from the action bar.

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

# Source provenance

Initial QML/JS/Python resources extracted from the owner’s local repository
`git@github.com:x3ng/.dotfiles.git`, commit
ca444838e0cb2ad245f4ff4f38cc35dfb2e66cbe.
Only Git-tracked runtime resources were imported; legacy installers and service
units were not copied. Relative shared-component symlinks are preserved.
Personal greeter username and default wallpaper were removed.

No DMS source has been imported. The owner selected MIT for this project. No third-party license notices were
found in the imported files; future external contributions require source and
license tracking. The bundled Hyprland adapter also extracts appearance and
workspace layout functions from the same dotfiles revision.

The sleep bridge is an original implementation against logind's D-Bus API.
DMS's `core/internal/server/loginctl/monitor.go` at
`f42d9b7149cf32bac7fdb5a2622bd894fd1b2cf6` was read as an architectural reference
for separating idle policy from sleep coordination; no source was copied.

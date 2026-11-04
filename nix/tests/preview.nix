{ pkgs, packages }:
pkgs.runCommand "nullshell-preview-check"
  {
    nativeBuildInputs = [
      pkgs.dbus
      pkgs.coreutils
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/config" XDG_STATE_HOME="$HOME/state"
    export XDG_CACHE_HOME="$HOME/cache" XDG_RUNTIME_DIR="$TMPDIR/runtime"
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
    export DBUS_SYSTEM_BUS_ADDRESS=unix:path="$TMPDIR/no-system-bus"
    unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE
    mkdir -p $out
    for mode in greeter lock polkit; do
      for light in 0 1; do
        export QS_PREVIEW_LIGHT=$light
        log="$out/$mode-$light.log"
        status=0
      timeout 4s dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- \
          ${packages.preview}/bin/nullshell-preview-$mode >"$log" 2>&1 || status=$?
        # A healthy preview remains open until the test timeout.
        if [ "$status" != 124 ]; then cat "$log"; exit 1; fi
        if ! grep -q 'Configuration Loaded' "$log"; then cat "$log"; exit 1; fi
        if grep -Ei 'failed to load|TypeError|ReferenceError|SyntaxError|is not a type|Cannot assign' "$log"; then
          exit 1
        fi
      done
    done
  ''

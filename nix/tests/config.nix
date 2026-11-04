{ pkgs }:
let
  source = pkgs.lib.fileset.toSource {
    root = ../..;
    fileset = pkgs.lib.fileset.unions [
      ../../qml
      ../../tests
    ];
  };
in
pkgs.runCommand "nullshell-config-check"
  {
    nativeBuildInputs = [
      pkgs.quickshell
      pkgs.python3
      pkgs.dbus
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/config" XDG_STATE_HOME="$HOME/state"
    export XDG_CACHE_HOME="$HOME/cache" XDG_RUNTIME_DIR="$TMPDIR/runtime"
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$out"
    chmod 700 "$XDG_RUNTIME_DIR"
    export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
    export DBUS_SYSTEM_BUS_ADDRESS=unix:path="$TMPDIR/no-system-bus"
    unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE
    dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- \
      python3 ${source}/tests/test_config.py "$out/config.log"
  ''

{ pkgs, helper }:
pkgs.runCommand "nullshell-bluetooth-check"
  {
    nativeBuildInputs = [
      pkgs.dbus
      (pkgs.python3.withPackages (p: [ p.dbus-next ]))
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME" "$out"
    dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- \
      python3 ${../../tests/test_bluetooth.py} ${helper}/bin/nullshell-helper > "$out/result.log" 2>&1 \
      || { cat "$out/result.log"; exit 1; }
    cat "$out/result.log"
  ''

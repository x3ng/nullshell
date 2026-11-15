{ pkgs, packages }:
pkgs.runCommand "nullshell-sleep-protocol-check"
  {
    nativeBuildInputs = [
      pkgs.dbus
      (pkgs.python3.withPackages (p: [ p.dbus-next ]))
    ];
  }
  ''
    mkdir -p "$out"
    python3 ${../../tests/test_sleep_bridge.py} ${packages.helper}/bin/nullshell-helper > "$out/result.log" 2>&1 \
      || { cat "$out/result.log"; exit 1; }
  ''

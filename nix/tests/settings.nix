{ pkgs, packages }:
let
  source = pkgs.lib.fileset.toSource {
    root = ../..;
    fileset = pkgs.lib.fileset.unions [
      ../../tests/test_settings_portal.py
      ../../integration
    ];
  };
in
pkgs.runCommand "nullshell-settings-protocol-check"
  {
    NULLSHELL_TEST_PORTAL = "${pkgs.xdg-desktop-portal}/libexec/xdg-desktop-portal";
    nativeBuildInputs = [
      pkgs.dbus
      (pkgs.python3.withPackages (p: [ p.dbus-next ]))
    ];
  }
  ''
    mkdir -p "$out"
    python3 ${source}/tests/test_settings_portal.py ${packages.helper}/bin/nullshell-helper > "$out/result.log" 2>&1 \
      || { cat "$out/result.log"; exit 1; }
  ''

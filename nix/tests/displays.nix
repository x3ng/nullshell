{ pkgs, packages }:
let
  source = pkgs.lib.fileset.toSource {
    root = ../..;
    fileset = pkgs.lib.fileset.unions [
      ../../DisplayProfiles.qml
      ../../adapters/DisplayTrial.lua
      ../../components/HyprlandControlCommands.js
      ../../components/DisplayGeometry.js
      ../../tests/test_displays.py
      ../../tests/test_display_trial.lua
      ../../tests/display_geometry.qml
      ../../tests/test_display_geometry.py
    ];
  };
in
pkgs.runCommand "nullshell-display-check"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.quickshell
      pkgs.luajit
    ];
  }
  ''
    mkdir -p "$out"
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    python3 ${source}/tests/test_display_geometry.py > "$out/geometry.log" 2>&1 || { cat "$out/geometry.log"; exit 1; }
    luajit ${source}/tests/test_display_trial.lua ${source}/adapters/DisplayTrial.lua > "$out/trial.log" 2>&1 || { cat "$out/trial.log"; exit 1; }
    python3 ${source}/tests/test_displays.py ${packages.helper}/bin/nullshell-helper > "$out/displays.log" 2>&1 || { cat "$out/displays.log"; exit 1; }
  ''

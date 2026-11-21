{ pkgs, packages }:
let
  source = pkgs.lib.fileset.toSource {
    root = ../..;
    fileset = pkgs.lib.fileset.unions [
      ../../DisplayProfiles.qml
      ../../adapters/DisplayTrial.lua
      ../../components/HyprlandControlCommands.js
      ../../tests/test_displays.py
      ../../tests/test_display_trial.lua
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
    luajit ${source}/tests/test_display_trial.lua ${source}/adapters/DisplayTrial.lua > "$out/trial.log" 2>&1 || { cat "$out/trial.log"; exit 1; }
    python3 ${source}/tests/test_displays.py ${packages.helper}/bin/nullshell-helper > "$out/displays.log" 2>&1 || { cat "$out/displays.log"; exit 1; }
  ''

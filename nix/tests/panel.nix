{ pkgs, packages }:
let
  source = pkgs.lib.fileset.toSource {
    root = ../..;
    fileset = pkgs.lib.fileset.unions [
      ../../tests/run_panel_headless.py
      ../../tests/test_panel_preview.py
    ];
  };
in
pkgs.runCommand "nullshell-panel-interaction-check"
  {
    nativeBuildInputs = [
      pkgs.quickshell
      pkgs.labwc
      (pkgs.python3.withPackages (p: [ p.pillow ]))
      pkgs.wtype
      pkgs.grim
      pkgs.mesa.llvmpipeHook
    ];
    FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; };
  }
  ''
    mkdir -p "$out"
    python3 ${source}/tests/run_panel_headless.py \
      --qml ${packages.assets}/share/nullshell/preview-panel.qml \
      --screenshots "$out/screenshots" --keyboard > "$out/result.log" 2>&1 \
      || { cat "$out/result.log"; exit 1; }
  ''

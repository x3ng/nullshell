{ pkgs, packages }:
let
  source = pkgs.lib.fileset.toSource {
    root = ../..;
    fileset = pkgs.lib.fileset.unions [
      ../../AppearanceState.qml
      ../../Appearance.qml
      ../../AppearanceExport.qml
      ../../AppearanceSnapshot.qml
      ../../AppearanceRules.js
      ../../Theme.qml
      ../../SurfaceCapabilities.qml
      ../../components
      ../../WallpaperState.qml
      ../../WallpaperExport.qml
      ../../GreeterWallpaper.qml
      ../../WallpaperImage.qml
      ../../tests/test_appearance.py
      ../../tests/test_wallpaper.py
    ];
  };
in
pkgs.runCommand "nullshell-appearance-check"
  {
    nativeBuildInputs = [
      pkgs.quickshell
      pkgs.python3
    ];
  }
  ''
    mkdir -p "$out"
    python3 ${source}/tests/test_wallpaper.py ${packages.helper}/bin/nullshell-helper > "$out/wallpaper.log" 2>&1 || { cat "$out/wallpaper.log"; exit 1; }
    python3 ${source}/tests/test_appearance.py ${packages.helper}/bin/nullshell-helper > "$out/result.log" 2>&1 || { cat "$out/result.log"; exit 1; }
  ''

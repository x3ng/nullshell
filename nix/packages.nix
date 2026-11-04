{ pkgs }:
let
  inherit (pkgs) lib;
  assets = pkgs.runCommand "nullshell-assets" { } ''
    mkdir -p $out/share/nullshell
    cp -R ${../qml}/. $out/share/nullshell/
    if find -L $out/share/nullshell -type l | read -r broken; then
      echo "Broken resource symlink: $broken" >&2
      exit 1
    fi
  '';
  runtime = with pkgs; [
    quickshell
    bash
    coreutils
    systemd
    python3
    bluez
    networkmanager
    brightnessctl
    hyprland
    wvkbd
    darkman
  ];
  desktop =
    pkgs.runCommand "nullshell-desktop"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta.mainProgram = "nullshell";
      }
      ''
        mkdir -p $out/bin
        makeWrapper ${pkgs.runtimeShell} $out/bin/nullshell \
          --add-flags ${../bin/nullshell} \
          --set NULLSHELL_DATA_DIR ${assets}/share/nullshell \
          --prefix PATH : ${lib.makeBinPath runtime}
      '';
  greeter =
    pkgs.runCommand "nullshell-greeter"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta.mainProgram = "nullshell-greeter";
      }
      ''
        mkdir -p $out/bin
        makeWrapper ${pkgs.runtimeShell} $out/bin/nullshell-greeter \
          --add-flags '${../bin/nullshell} greeter' \
          --set NULLSHELL_DATA_DIR ${assets}/share/nullshell \
          --prefix PATH : ${
            lib.makeBinPath [
              pkgs.quickshell
              pkgs.systemd
              pkgs.coreutils
            ]
          }
      '';
  preview =
    pkgs.runCommand "nullshell-preview"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        mkdir -p $out/bin
        for mode in lock greeter polkit; do
          makeWrapper ${pkgs.runtimeShell} $out/bin/nullshell-preview-$mode \
            --add-flags "${../bin/nullshell} preview-$mode" \
            --set NULLSHELL_DATA_DIR ${assets}/share/nullshell \
            --prefix PATH : ${
              lib.makeBinPath [
                pkgs.quickshell
                pkgs.coreutils
              ]
            }
        done
      '';
in
{
  inherit
    assets
    desktop
    greeter
    preview
    ;
  default = desktop;
}

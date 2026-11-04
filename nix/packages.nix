{ pkgs }:
let
  inherit (pkgs) lib;
  helper = import ./backend.nix { inherit pkgs; };
  assets = pkgs.runCommand "nullshell-assets" { } ''
    mkdir -p $out/share/nullshell
    cp ${../integration/hypridle.conf} $out/share/nullshell/hypridle.conf
    cp -R ${../qml}/. $out/share/nullshell/
    if find -L $out/share/nullshell -type l | read -r broken; then
      echo "Broken resource symlink: $broken" >&2
      exit 1
    fi
  '';
  runtime = with pkgs; [
    helper
    quickshell
    bash
    coreutils
    systemd
    bluez
    networkmanager
    brightnessctl
    hyprland
    hypridle
    wvkbd
    darkman
    util-linux
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
          --set-default NULLSHELL_DATA_DIR ${assets}/share/nullshell \
          --set NULLSHELL_LIBEXEC_DIR ${../bin} \
          --prefix PATH : "$out/bin:${lib.makeBinPath runtime}"
        mkdir -p $out/lib/systemd/user
        for unit in ${../integration/systemd}/*; do
          sed "s|@BINDIR@|$out/bin|g; s|/bin/sh|${pkgs.runtimeShell}|g" "$unit" > "$out/lib/systemd/user/$(basename "$unit")"
        done
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
          --set-default NULLSHELL_DATA_DIR ${assets}/share/nullshell \
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
        for mode in lock greeter polkit connectivity panel; do
          makeWrapper ${pkgs.runtimeShell} $out/bin/nullshell-preview-$mode \
            --add-flags "${../bin/nullshell} preview-$mode" \
            --set-default NULLSHELL_DATA_DIR ${assets}/share/nullshell \
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
    helper
    ;
  default = desktop;
}

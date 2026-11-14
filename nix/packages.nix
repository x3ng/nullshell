{ pkgs }:
let
  inherit (pkgs) lib;
  helper = import ./backend.nix { inherit pkgs; };
  # Keep source packaging independent of backend/docs and their build outputs.
  qmlSource = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions (
      map (name: ../. + "/${name}") (
        builtins.filter (name: lib.hasSuffix ".qml" name || lib.hasSuffix ".js" name) (
          builtins.attrNames (builtins.readDir ../.)
        )
      )
      ++ [
        ../components
        ../adapters
        ../greeter
        ../lock
        ../polkit
        ../preview
        ../wallpaper.json
        ../greeter-interface.version
      ]
      ++ lib.optionals (builtins.pathExists ../assets) [ ../assets ]
    );
  };
  assets = pkgs.runCommand "nullshell-assets" { } ''
    mkdir -p $out/share/nullshell
    cp ${../integration/hypridle.conf} $out/share/nullshell/hypridle.conf
    cp -R ${qmlSource}/. $out/share/nullshell/
    if find -L $out/share/nullshell -type l | read -r broken; then
      echo "Broken resource symlink: $broken" >&2
      exit 1
    fi
  '';
  runtimeDependencies = with pkgs; [
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
    glib
    util-linux
  ];
  schemaPath = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}";
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
          --prefix XDG_DATA_DIRS : "${schemaPath}" \
          --prefix PATH : "$out/bin:${lib.makeBinPath runtimeDependencies}"
      '';
  # No QML snapshot dependency: editing the checkout does not rebuild runtime.
  runtime =
    pkgs.runCommand "nullshell-runtime"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta.mainProgram = "nullshell";
      }
      ''
        mkdir -p $out/bin
        makeWrapper ${pkgs.runtimeShell} $out/bin/nullshell \
          --add-flags ${../bin/nullshell} \
          --set NULLSHELL_LIBEXEC_DIR ${../bin} \
          --set NULLSHELL_SLEEP_CONFIG ${../integration/hypridle.conf} \
          --prefix XDG_DATA_DIRS : "${schemaPath}" \
          --prefix PATH : "$out/bin:${lib.makeBinPath runtimeDependencies}"
        # Direct `quickshell -c nullshell` gets the same optional backend tools.
        makeWrapper ${pkgs.quickshell}/bin/quickshell $out/bin/quickshell \
          --prefix XDG_DATA_DIRS : "${schemaPath}" \
          --prefix PATH : "$out/bin:${lib.makeBinPath runtimeDependencies}"
        ln -s ${helper}/bin/nullshell-helper $out/bin/nullshell-helper
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
          --set-default NULLSHELL_PACKAGED_DATA_DIR ${assets}/share/nullshell \
          --prefix PATH : ${
            lib.makeBinPath [
              pkgs.quickshell
              pkgs.systemd
              pkgs.coreutils
              pkgs.util-linux
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
    runtime
    greeter
    preview
    helper
    ;
  default = desktop;
}

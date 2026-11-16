{ pkgs }:
let
  inherit (pkgs) lib;
  helper = import ./backend.nix { inherit pkgs; };
  settingsPortal = pkgs.runCommand "nullshell-settings-portal" { } ''
    mkdir -p $out/share/xdg-desktop-portal/portals $out/share/dbus-1/services $out/share/applications
    cp ${../integration/nullshell.portal} $out/share/xdg-desktop-portal/portals/nullshell.portal
    cp ${../integration/org.nullshell.desktop.desktop} $out/share/applications/org.nullshell.desktop.desktop
    substitute ${../integration/org.freedesktop.impl.portal.desktop.nullshell.service.in} \
      $out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.nullshell.service \
      --replace-fail '@HELPER@' '${helper}/bin/nullshell-helper'
  '';
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
    # Networking/Bluetooth use system D-Bus services through native APIs.
    # Their daemons are host choices, not CLI dependencies of this runtime.
    brightnessctl
    hyprland
    wvkbd
    util-linux
  ];
  # No QML snapshot dependency: editing the checkout does not rebuild runtime.
  launcher =
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
          --prefix PATH : "$out/bin:${lib.makeBinPath runtimeDependencies}"
      '';
  # Aggregate native upstream binaries; never shadow quickshell with a wrapper.
  runtime = pkgs.buildEnv {
    name = "nullshell-runtime";
    paths = [ launcher ] ++ runtimeDependencies;
    pathsToLink = [ "/bin" ];
    meta.mainProgram = "nullshell";
  };
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
    runtime
    greeter
    preview
    helper
    settingsPortal
    ;
  default = runtime;
}

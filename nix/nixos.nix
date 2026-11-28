{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nullshell;
  packages = import ./packages.nix { inherit pkgs; };
  appearance = cfg.greeter.appearance;
  syncAppearance = cfg.greeter.enable && appearance.enable;
  appearanceEnvValue = if syncAppearance then appearance.directory else "off";
  greeterInstaller = pkgs.writeShellApplication {
    name = "nullshell-install-greeter";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.util-linux
    ];
    text = ''
      exec ${pkgs.runtimeShell} ${../bin/nullshell-install-greeter} \
        --destination ${lib.escapeShellArg cfg.greeter.interfaceDirectory} "$@"
    '';
  };
  greeterSession = pkgs.writeShellScript "nullshell-greeter-session" ''
    umask 077
    export NULLSHELL_GREETER_OVERRIDE_DIR=${lib.escapeShellArg cfg.greeter.interfaceDirectory}
    export NULLSHELL_APPEARANCE_DIR=${lib.escapeShellArg appearanceEnvValue}
    export NULLSHELL_GREETER_STATE_FILE=/var/lib/nullshell-greeter/last-login.json
    export XDG_CACHE_HOME=/var/cache/nullshell-greeter
    # greetd starts outside the user's session environment. Add the NixOS
    # system profile here, not in the portable session catalog.
    export XDG_DATA_DIRS="''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}:/run/current-system/sw/share"
    exec ${pkgs.dbus}/bin/dbus-run-session -- ${pkgs.cage}/bin/cage -s -d -- ${cfg.greeter.package}/bin/nullshell-greeter
  '';
in
{
  options.programs.nullshell = {
    enable = lib.mkEnableOption "nullshell runtime and desktop system integration";
    appearance.portal.enable = lib.mkEnableOption "nullshell Settings portal backend for the Hyprland session";
    greeter = {
      enable = lib.mkEnableOption "the nullshell greetd interface";
      interfaceDirectory = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/nullshell-greeter-ui";
        description = "Root-managed optional QML override. Absent installation uses the packaged interface.";
      };
      appearance = {
        enable =
          lib.mkEnableOption "per-user desktop theme and wallpaper synchronization with the greeter"
          // {
            default = true;
          };
        directory = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/nullshell-appearance";
          description = "Dedicated per-user theme slot root, separate from greeter authentication state.";
        };
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = packages.greeter;
      };
    };
  };
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = [ packages.runtime ];
      security.pam.services.nullshell-lock = { };
      security.polkit.enable = true;
      services.upower.enable = true;
    })
    (lib.mkIf (cfg.enable && cfg.appearance.portal.enable) {
      xdg.portal.enable = true;
      xdg.portal.extraPortals = [ packages.settingsPortal ];
      xdg.portal.config.hyprland."org.freedesktop.impl.portal.Settings" = [
        "nullshell"
        "gtk"
      ];
      services.dbus.packages = [ packages.settingsPortal ];
      environment.systemPackages = [ packages.settingsPortal ];
    })
    (lib.mkIf syncAppearance {
      assertions = [
        {
          assertion =
            lib.hasPrefix "/" appearance.directory
            && builtins.match ".*[[:space:]%].*" appearance.directory == null
            && appearance.directory != "/"
            && appearance.directory != "/var/lib/nullshell-greeter";
          message = "nullshell greeter appearance.directory must be a dedicated absolute path without whitespace or tmpfiles specifiers.";
        }
      ];
      # Root owns the 0711 slot container; each ordinary user gets an isolated
      # 2750 <user>:greeter directory without configuring usernames.
      systemd.tmpfiles.rules = [
        "d ${appearance.directory} 0711 root root -"
        "d ${appearance.directory}/users 0711 root root -"
      ];
      systemd.services.nullshell-appearance-slots = {
        description = "Provision per-user nullshell greeter appearance slots";
        wantedBy = [ "multi-user.target" ];
        after = [
          "systemd-tmpfiles-setup.service"
          "systemd-tmpfiles-resetup.service"
        ];
        before = [
          "greetd.service"
          "systemd-user-sessions.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${packages.helper}/bin/nullshell-helper ensure-appearance-slot --root ${lib.escapeShellArg appearance.directory} --local";
        };
      };
      systemd.services."user@".serviceConfig.ExecStartPre = [
        "-${packages.helper}/bin/nullshell-helper ensure-appearance-slot --root ${lib.escapeShellArg appearance.directory} %i"
      ];
    })
    (lib.mkIf
      (
        cfg.greeter.enable
        && (!appearance.enable || appearance.directory != "/var/lib/nullshell-appearance")
      )
      {
        environment.sessionVariables.NULLSHELL_APPEARANCE_DIR = appearanceEnvValue;
      }
    )
    (lib.mkIf cfg.greeter.enable {
      environment.systemPackages = [ greeterInstaller ];
      assertions = [
        {
          assertion =
            lib.hasPrefix "/" cfg.greeter.interfaceDirectory
            && cfg.greeter.interfaceDirectory != "/"
            && cfg.greeter.interfaceDirectory != "/var/lib/nullshell-greeter"
            && cfg.greeter.interfaceDirectory != appearance.directory;
          message = "greeter.interfaceDirectory must be an absolute dedicated directory, separate from authentication and theme data.";
        }
      ];
      systemd.tmpfiles.rules = [
        "d /var/lib/nullshell-greeter 0700 greeter greeter -"
        "d /var/cache/nullshell-greeter 0700 greeter greeter -"
      ];
      services.greetd = {
        enable = true;
        settings.default_session = {
          user = "greeter";
          command = "${greeterSession}";
        };
      };
    })
  ];
}

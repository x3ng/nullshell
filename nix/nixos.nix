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
  appearanceFile = "${appearance.directory}/theme.json";
  wallpaperFile = "${appearance.directory}/wallpaper.json";
  syncAppearance = cfg.greeter.enable && appearance.sourceUser != null;
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
    ${lib.optionalString syncAppearance "export NULLSHELL_APPEARANCE_FILE=${lib.escapeShellArg appearanceFile}"}
    ${lib.optionalString syncAppearance "export NULLSHELL_WALLPAPER_FILE=${lib.escapeShellArg wallpaperFile}"}
    export NULLSHELL_GREETER_STATE_FILE=/var/lib/nullshell-greeter/last-login.json
    exec ${pkgs.dbus}/bin/dbus-run-session -- ${pkgs.cage}/bin/cage -s -d -- ${cfg.greeter.package}/bin/nullshell-greeter
  '';
in
{
  options.programs.nullshell = {
    enable = lib.mkEnableOption "nullshell PAM and desktop system integration";
    greeter = {
      enable = lib.mkEnableOption "the nullshell greetd interface";
      interfaceDirectory = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/nullshell-greeter-ui";
        description = "Root-managed optional QML override. Absent installation uses the packaged interface.";
      };
      appearance = {
        sourceUser = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Account allowed to publish its appearance for the greeter; null disables synchronization.";
        };
        directory = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/nullshell-appearance";
          description = "Dedicated mutable theme directory, separate from greeter authentication state.";
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
      security.pam.services.nullshell-lock = { };
      security.polkit.enable = true;
      services.upower.enable = true;
    })
    (lib.mkIf syncAppearance {
      assertions = [
        {
          assertion =
            builtins.hasAttr appearance.sourceUser config.users.users
            && config.users.users.${appearance.sourceUser}.isNormalUser;
          message = "nullshell greeter appearance.sourceUser must name a configured normal user.";
        }
        {
          assertion =
            lib.hasPrefix "/" appearance.directory
            && builtins.match ".*[[:space:]%].*" appearance.directory == null
            && appearance.directory != "/"
            && appearance.directory != "/var/lib/nullshell-greeter";
          message = "nullshell greeter appearance.directory must be a dedicated absolute path without whitespace or tmpfiles specifiers.";
        }
      ];
      # Root controls the greeter's launch path; only the selected user writes
      # theme data. setgid + explicit 0640 exports give greeter read access.
      systemd.tmpfiles.rules = [
        "d ${appearance.directory} 2750 ${appearance.sourceUser} greeter -"
      ]
      ++ map (name: "z ${appearance.directory}/${name} 0640 ${appearance.sourceUser} greeter -") [
        "theme.json"
        "wallpaper.json"
        "wallpaper-0.img"
        "wallpaper-1.img"
      ]
      ++ map (name: "z ${appearance.directory}/${name} 0600 ${appearance.sourceUser} greeter -") [
        ".appearance.lock"
        ".wallpaper.lock"
      ];
      environment.sessionVariables = {
        NULLSHELL_APPEARANCE_SOURCE_USER = appearance.sourceUser;
        NULLSHELL_APPEARANCE_EXPORT_FILE = appearanceFile;
        NULLSHELL_WALLPAPER_EXPORT_FILE = wallpaperFile;
      };
    })
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
      systemd.tmpfiles.rules = [ "d /var/lib/nullshell-greeter 0700 greeter greeter -" ];
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

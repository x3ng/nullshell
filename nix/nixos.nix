{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nullshell;
  packages = import ./packages.nix { inherit pkgs; };
  greeterSession = pkgs.writeShellScript "nullshell-greeter-session" ''
    umask 077
    export NULLSHELL_GREETER_STATE_FILE=/var/lib/nullshell-greeter/last-login.json
    exec ${pkgs.dbus}/bin/dbus-run-session -- ${pkgs.cage}/bin/cage -s -d -- ${cfg.greeter.package}/bin/nullshell-greeter
  '';
in
{
  options.programs.nullshell = {
    enable = lib.mkEnableOption "nullshell PAM and desktop system integration";
    greeter = {
      enable = lib.mkEnableOption "the nullshell greetd interface";
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
    (lib.mkIf cfg.greeter.enable {
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

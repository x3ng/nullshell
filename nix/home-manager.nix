{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nullshell;
  packages = import ./packages.nix { inherit pkgs; };
in
{
  options.programs.nullshell = {
    enable = lib.mkEnableOption "nullshell desktop runtime";
    editable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Load QML from XDG_CONFIG_HOME/quickshell/nullshell; install only the runtime dependencies and helper.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = if cfg.editable then packages.runtime else packages.desktop;
      description = "Packaged nullshell desktop runtime.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    # Reload after Home Manager removes units from older generations. Do not
    # stop/restart existing authentication processes during activation.
    home.activation.nullshellUnits = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ -n "''${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
        run ${pkgs.systemd}/bin/systemctl --user daemon-reload
      fi
    '';
  };
}

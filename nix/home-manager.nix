{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nullshell;
  packages = import ./packages.nix { inherit pkgs; };
  units = builtins.attrNames (builtins.readDir ../integration/systemd);
in
{
  options.programs.nullshell = {
    enable = lib.mkEnableOption "nullshell desktop packages and session-scoped units";
    editable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Load QML from XDG_CONFIG_HOME/quickshell/nullshell; install only the runtime and services.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = if cfg.editable then packages.runtime else packages.desktop;
      description = "Packaged nullshell desktop runtime.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    xdg.configFile = lib.genAttrs (map (name: "systemd/user/${name}") units) (target: {
      source = "${cfg.package}/lib/${target}";
    });
    # Deliberately no WantedBy links and no activation-time service restarts.
    home.activation.nullshellUnits = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ -n "''${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
        run ${pkgs.systemd}/bin/systemctl --user daemon-reload
      fi
    '';
  };
}

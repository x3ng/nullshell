{
  description = "nullshell: an on-demand desktop shell built with Quickshell";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs =
    { self, nixpkgs }:
    let
      eachSystem = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      nixosModules.default = import ./nix/nixos.nix;
      packages = eachSystem (
        system:
        import ./nix/packages.nix {
          pkgs = nixpkgs.legacyPackages.${system};
        }
      );
      checks = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          packages = self.packages.${system};
        in
        {
          inherit (packages) greeter runtime;
          panel = import ./nix/tests/panel.nix { inherit pkgs packages; };
          preview = import ./nix/tests/preview.nix { inherit pkgs packages; };
          config = import ./nix/tests/config.nix { inherit pkgs; };
          command-panel = import ./nix/tests/command-panel.nix { inherit pkgs; };
          settings = import ./nix/tests/settings.nix { inherit pkgs packages; };
          sleep = import ./nix/tests/sleep.nix { inherit pkgs packages; };
          session = import ./nix/tests/session.nix { inherit pkgs; };
          appearance = import ./nix/tests/appearance.nix { inherit pkgs packages; };
          migration = import ./nix/tests/migration.nix { inherit pkgs; };
          bluetooth = import ./nix/tests/bluetooth.nix {
            inherit pkgs;
            helper = packages.helper;
          };
        }
      );
      # Explicit, heavier integration test; not part of every local flake check.
      legacyPackages = eachSystem (system: {
        tests.launch-vm = import ./nix/tests/launch-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
        };
        tests.desktop-vm = import ./nix/tests/desktop-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          packages = self.packages.${system};
        };
        tests.greeter-vm = import ./nix/tests/greeter-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          packages = self.packages.${system};
        };
        tests.lock-vm = import ./nix/tests/lock-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          packages = self.packages.${system};
        };
        tests.vm = import ./nix/tests/vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          packages = self.packages.${system};
        };
      });
      apps = eachSystem (
        system:
        builtins.listToAttrs (
          map
            (mode: {
              name = "preview-${mode}";
              value = {
                type = "app";
                program = "${self.packages.${system}.preview}/bin/nullshell-preview-${mode}";
                meta.description = "Visual-only ${mode} preview; no authentication";
              };
            })
            [
              "greeter"
              "lock"
              "polkit"
              "connectivity"
              "panel"
            ]
        )
      );
      devShells = eachSystem (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          packages = with nixpkgs.legacyPackages.${system}; [
            quickshell
            qt6.qtdeclarative
            (python3.withPackages (p: [
              p.dbus-next
              p.pillow
            ]))
            dbus
            glib
            grim
            wtype
            labwc
            nixfmt
            cargo
            rustc
            clippy
            rustfmt
          ];
          shellHook = ''
            export PATH="$PWD/bin:$PATH"
          '';
          CARGO_BUILD_JOBS = "2";
        };
      });
      formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}

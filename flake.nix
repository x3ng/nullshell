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
      homeManagerModules.default = import ./nix/home-manager.nix;
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
          inherit (packages) desktop greeter;
          preview = import ./nix/tests/preview.nix { inherit pkgs packages; };
          config = import ./nix/tests/config.nix { inherit pkgs; };
          migration = import ./nix/tests/migration.nix { inherit pkgs; };
          bluetooth = import ./nix/tests/bluetooth.nix {
            inherit pkgs;
            helper = packages.helper;
          };
        }
      );
      # Explicit, heavier integration test; not part of every local flake check.
      legacyPackages = eachSystem (system: {
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
            ]
        )
      );
      devShells = eachSystem (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          packages = with nixpkgs.legacyPackages.${system}; [
            quickshell
            qt6.qtdeclarative
            nixfmt
            cargo
            rustc
            clippy
            rustfmt
          ];
          CARGO_BUILD_JOBS = "2";
        };
      });
      formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}

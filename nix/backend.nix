{ pkgs }:
pkgs.rustPlatform.buildRustPackage {
  pname = "nullshell-helper";
  version = "0.1.0";
  src = pkgs.lib.fileset.toSource {
    root = ../backend;
    fileset = pkgs.lib.fileset.unions [
      ../backend/Cargo.toml
      ../backend/Cargo.lock
      ../backend/src
    ];
  };
  cargoLock.lockFile = ../backend/Cargo.lock;
  meta = {
    license = pkgs.lib.licenses.mit;
    mainProgram = "nullshell-helper";
    platforms = pkgs.lib.platforms.linux;
  };
}

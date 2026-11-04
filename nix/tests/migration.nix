{ pkgs }:
let
  source = pkgs.lib.fileset.toSource {
    root = ../..;
    fileset = pkgs.lib.fileset.unions [
      ../../bin
      ../../tests
    ];
  };
in
pkgs.runCommand "nullshell-migration-check"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.util-linux
    ];
  }
  ''
    mkdir -p "$out"
    python3 ${source}/tests/test_migration.py > "$out/result.log"
  ''

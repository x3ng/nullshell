{ pkgs }:
let
  source = pkgs.lib.fileset.toSource {
    root = ../..;
    fileset = pkgs.lib.fileset.unions [
      ../../SessionActions.qml
      ../../tests/session_actions.qml
      ../../tests/test_session_actions.py
    ];
  };
in
pkgs.runCommand "nullshell-session-actions-check"
  {
    nativeBuildInputs = [
      pkgs.quickshell
      pkgs.python3
    ];
  }
  ''
    mkdir -p "$out"
    python3 ${source}/tests/test_session_actions.py > "$out/result.log" 2>&1 \
      || { cat "$out/result.log"; exit 1; }
  ''

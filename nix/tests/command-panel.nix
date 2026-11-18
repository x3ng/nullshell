{ pkgs }:
let
  source = pkgs.lib.fileset.toSource {
    root = ../..;
    fileset = pkgs.lib.fileset.unions [
      ../../adapters/HyprlandBindings.qml
      ../../ApplicationLauncher.qml
      ../../DesktopSearch.qml
      ../../ShellActions.qml
      ../../SessionActions.qml
      ../../preview/PanelFixture.qml
      ../../SearchQuery.js
      ../../SearchMatch.js
      ../../ConfigRules.js
      ../../Notifications.qml
      ../../NotificationQuiet.qml
      ../../components/NotificationUtils.js
      ../../tests/command_panel.qml
      ../../tests/test_command_panel.py
    ];
  };
in
pkgs.runCommand "nullshell-command-check"
  {
    nativeBuildInputs = [
      pkgs.quickshell
      pkgs.dbus
      (pkgs.python3.withPackages (p: [ p.dbus-next ]))
    ];
  }
  ''
    mkdir -p "$out"
    python3 ${source}/tests/test_command_panel.py > "$out/result.log" 2>&1 \
      || { cat "$out/result.log"; exit 1; }
  ''

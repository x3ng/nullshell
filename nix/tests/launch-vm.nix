{ pkgs }:
let
  application = pkgs.writeShellScript "synthetic-application" ''
    printf '%s\n' "$WAYLAND_DISPLAY" "$XDG_DATA_HOME" "$PWD" "$@" > "$XDG_RUNTIME_DIR/launch-context"
    ${pkgs.coreutils}/bin/cat /proc/self/cgroup > "$XDG_RUNTIME_DIR/launch-cgroup"
    echo $$ > "$XDG_RUNTIME_DIR/launch-pid"
    exec ${pkgs.coreutils}/bin/sleep 60
  '';
  entry = pkgs.writeText "launch-test.qml" ''
    import QtQuick
    import Quickshell
    ShellRoot {
      id: root
      property bool queued: false
      property int failures: 0
      ApplicationLauncher {
        id: launcher
        onFeedback: (key, summary, body, critical) => {
          if (summary !== "Could not launch Missing") Qt.exit(1);
          root.failures++;
        }
      }
      Component.onCompleted: {
        launcher.launch({name: "Synthetic", command: ["${application}", "$literal", "a b", "`literal`"], workingDirectory: "/tmp", runInTerminal: false}, [], false);
        launcher.launch({name: "Missing", command: ["/nullshell-test-missing"], workingDirectory: "/tmp", runInTerminal: false}, [], false);
        queued = true;
      }
      Timer {
        interval: 50; running: true; repeat: true
        onTriggered: if (root.queued && launcher.jobs.length === 0) {
          if (root.failures !== 1) Qt.exit(1);
          console.log("LAUNCH_VM_OK");
          Qt.quit();
        }
      }
      Timer { interval: 20000; running: true; onTriggered: Qt.exit(1) }
    }
  '';
  resources = pkgs.runCommand "nullshell-launch-integration-resources" { } ''
    mkdir -p "$out"
    cp ${../../ApplicationLauncher.qml} "$out/ApplicationLauncher.qml"
    cp ${entry} "$out/shell.qml"
  '';
  runner = pkgs.writeShellScript "launch-check" ''
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.quickshell
        pkgs.systemd
        pkgs.coreutils
      ]
    }
    export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
    export WAYLAND_DISPLAY=synthetic-wayland XDG_DATA_HOME="$XDG_RUNTIME_DIR/synthetic-data"
    quickshell --path ${resources}/shell.qml > "$XDG_RUNTIME_DIR/launch-check.log" 2>&1
  '';
in
pkgs.testers.runNixOSTest {
  name = "nullshell-application-launch";
  nodes.machine = { ... }: {
    virtualisation.cores = 2;
    virtualisation.memorySize = 1024;
    services.getty.autologinUser = "test";
    users.users.test = {
      isNormalUser = true;
      password = "test-only-password";
    };
    systemd.user.services.launch-check = {
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = runner;
        RemainAfterExit = true;
      };
    };
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_until_succeeds("grep LAUNCH_VM_OK /run/user/1000/launch-check.log")
    values = machine.succeed("cat /run/user/1000/launch-context").splitlines()
    assert values == ["synthetic-wayland", "/run/user/1000/synthetic-data", "/tmp", "$literal", "a b", "`literal`"], values
    assert "app.slice" in machine.succeed("cat /run/user/1000/launch-cgroup")
    # The launch client exited; its application is still independently alive.
    machine.sleep(2)
    machine.succeed("test -d /proc/$(cat /run/user/1000/launch-pid)")
    machine.succeed("! pgrep -u test -x quickshell")
  '';
}

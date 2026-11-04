{ pkgs, packages }:
let
  swayConfig = pkgs.writeText "nullshell-lock-test-sway" ''
    xwayland disable
    output HEADLESS-1 resolution 1280x720
    seat seat0 fallback true
    exec ${packages.desktop}/bin/nullshell locker
  '';
in
pkgs.testers.runNixOSTest {
  name = "nullshell-session-lock";
  nodes.machine = { ... }: {
    imports = [ ../nixos.nix ];
    programs.nullshell.enable = true;
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
    users.users.preview = {
      isNormalUser = true;
      # Synthetic VM-only account; never used in host deployment.
      password = "test-only-password";
    };
    environment.systemPackages = [
      packages.desktop
      pkgs.sway
      pkgs.wtype
      pkgs.dbus
      pkgs.pamtester
    ];
    fonts.packages = [ pkgs.dejavu_fonts ];
    systemd.services.lock-test-compositor = {
      path = [
        pkgs.bash
        pkgs.coreutils
        packages.desktop
      ];
      serviceConfig = {
        User = "preview";
        RuntimeDirectory = "nullshell-lock-test";
        RuntimeDirectoryMode = "0700";
        ExecStart = "${pkgs.dbus}/bin/dbus-run-session --dbus-daemon=${pkgs.dbus}/bin/dbus-daemon -- ${pkgs.sway}/bin/sway --config ${swayConfig}";
      };
      environment = {
        HOME = "/home/preview";
        USER = "preview";
        XDG_RUNTIME_DIR = "/run/nullshell-lock-test";
        WLR_BACKENDS = "headless";
        WLR_RENDERER = "pixman";
        WLR_LIBINPUT_NO_DEVICES = "1";
        QT_QUICK_BACKEND = "software";
      };
    };
  };
  testScript = ''
    import json
    import shlex
    from datetime import timedelta

    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test -f /etc/pam.d/nullshell-lock")
    machine.succeed("printf '%s\\n' test-only-password | su -s /bin/sh preview -c 'pamtester nullshell-lock preview authenticate'")
    machine.succeed("systemctl start lock-test-compositor")
    machine.wait_until_succeeds("test -S /run/nullshell-lock-test/wayland-1", timeout=timedelta(seconds=30))

    def user(command):
        return "su -s /bin/sh preview -c " + shlex.quote(
            "export XDG_RUNTIME_DIR=/run/nullshell-lock-test WAYLAND_DISPLAY=wayland-1; " + command
        )

    status = user("nullshell ipc locker call locker status")
    machine.wait_until_succeeds(status, timeout=timedelta(seconds=30))
    machine.succeed(user("nullshell lock"))
    assert json.loads(machine.succeed(status))["secure"]
    machine.succeed(user("wtype wrong-password -k Return"))
    machine.wait_until_succeeds("journalctl -u lock-test-compositor | grep 'authentication failure'", timeout=timedelta(seconds=15))
    machine.sleep(3)
    assert json.loads(machine.succeed(status))["secure"]
    machine.succeed(user("wtype -M ctrl -k a -m ctrl test-only-password -k Return"))
    machine.wait_until_succeeds(status + " | grep '\"locked\":false'", timeout=timedelta(seconds=15))
    # Successful authentication is the only unlock path; the process stays alive.
    assert not json.loads(machine.succeed(status))["secure"]
    machine.succeed("systemctl stop lock-test-compositor")
  '';
}

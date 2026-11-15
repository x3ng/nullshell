{ pkgs, packages }:
let
  swayConfig = pkgs.writeText "nullshell-lock-test-sway" ''
    xwayland disable
    output HEADLESS-1 resolution 1280x720
    seat seat0 fallback true
    exec ${packages.helper}/bin/nullshell-helper sleep-bridge > /run/nullshell-lock-test/sleep-bridge.log 2>&1
  '';
in
pkgs.testers.runNixOSTest {
  name = "nullshell-session-lock";
  nodes.machine = { ... }: {
    imports = [ ../nixos.nix ];
    programs.nullshell.enable = true;
    # Synthetic system-wide XDG configuration, owned only by this test VM.
    environment.etc."xdg/quickshell/nullshell".source = "${packages.assets}/share/nullshell";
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
    users.users.preview = {
      isNormalUser = true;
      # Synthetic VM-only account; never used in host deployment.
      password = "test-only-password";
    };
    environment.systemPackages = [
      packages.runtime
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
        packages.runtime
      ];
      serviceConfig = {
        User = "preview";
        PAMName = "login";
        RuntimeDirectory = "nullshell-lock-test";
        RuntimeDirectoryMode = "0700";
        ExecStart = "${pkgs.dbus}/bin/dbus-run-session --dbus-daemon=${pkgs.dbus}/bin/dbus-daemon -- ${pkgs.sway}/bin/sway --config ${swayConfig}";
      };
      environment = {
        HOME = "/home/preview";
        USER = "preview";
        XDG_SESSION_TYPE = "wayland";
        XDG_SESSION_CLASS = "user";
        XDG_RUNTIME_DIR = "/run/user/1000";
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
    machine.wait_until_succeeds("test -S /run/user/1000/wayland-1", timeout=timedelta(seconds=30))

    def user(command):
        return "su -s /bin/sh preview -c " + shlex.quote(
            "export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 QT_QUICK_BACKEND=software; " + command
        )

    status = user("nullshell ipc locker call locker status")
    try:
        machine.wait_until_succeeds("grep -F '\"event\":\"ready\"' /run/nullshell-lock-test/sleep-bridge.log", timeout=timedelta(seconds=30))
    except Exception:
        print(machine.succeed("cat /run/nullshell-lock-test/sleep-bridge.log; journalctl -u lock-test-compositor --no-pager"))
        raise
    pid = machine.succeed("systemctl show lock-test-compositor -p MainPID --value").strip()
    session_path = machine.succeed("busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager GetSessionByPID u " + pid).split('"')[1]
    session = machine.succeed("busctl get-property org.freedesktop.login1 " + session_path + " org.freedesktop.login1.Session Id").split('"')[1]
    assert session
    # A real logind request reaches the helper and starts an absent locker.
    machine.fail(status)
    machine.succeed("loginctl lock-session " + shlex.quote(session))
    machine.wait_until_succeeds(status + " | grep '\"secure\":true'", timeout=timedelta(seconds=15))
    machine.wait_until_succeeds("grep -F '\"event\":\"locked\"' /run/nullshell-lock-test/sleep-bridge.log", timeout=timedelta(seconds=15))
    # Direct lock remains idempotent and does not require the bridge.
    machine.succeed(user("nullshell lock"))
    assert json.loads(machine.succeed(status))["secure"]
    machine.succeed(user("wtype -s 200 wrong-password -k Return"))
    machine.wait_until_succeeds("journalctl --no-pager | grep -F 'pam_unix(nullshell-lock:auth): authentication failure'", timeout=timedelta(seconds=15))
    machine.sleep(3)
    assert json.loads(machine.succeed(status))["secure"]
    machine.succeed(user("wtype -s 200 -M ctrl -k a -m ctrl test-only-password -k Return"))
    machine.wait_until_succeeds(status + " | grep '\"locked\":false'", timeout=timedelta(seconds=15))
    # Successful authentication is the only unlock path; the process stays alive.
    assert not json.loads(machine.succeed(status))["secure"]
    machine.succeed("systemctl stop lock-test-compositor")
  '';
}

{ pkgs, packages }:
pkgs.testers.runNixOSTest {
  name = "nullshell-isolated-preview";
  nodes.machine = { ... }: {
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
    users.users.preview = {
      isNormalUser = true;
      uid = 1000;
    };
    environment.systemPackages = [
      packages.preview
      pkgs.dbus
      pkgs.coreutils
    ];
    systemd.services.nullshell-preview = {
      description = "VM-only unprivileged visual smoke test";
      serviceConfig = {
        User = "preview";
        RuntimeDirectory = "nullshell-preview";
        RuntimeDirectoryMode = "0700";
        ExecStart = "${pkgs.dbus}/bin/dbus-run-session --dbus-daemon=${pkgs.dbus}/bin/dbus-daemon -- ${packages.preview}/bin/nullshell-preview-greeter";
      };
      environment = {
        HOME = "/home/preview";
        XDG_RUNTIME_DIR = "/run/nullshell-preview";
        QT_QPA_PLATFORM = "offscreen";
        QT_QUICK_BACKEND = "software";
      };
    };
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    # Installation must not enable a shell in an unrelated session.
    machine.fail("systemctl is-active nullshell-preview.service")
    machine.succeed("systemctl start nullshell-preview.service")
    machine.wait_until_succeeds("journalctl -u nullshell-preview.service | grep 'Configuration Loaded'", timeout=30)
    machine.succeed("systemctl is-active nullshell-preview.service")
    machine.succeed("test $(systemctl show nullshell-preview.service -p User --value) = preview")
    machine.succeed("systemctl stop nullshell-preview.service")
    machine.fail("systemctl is-active nullshell-preview.service")
  '';
}

{ pkgs, packages }:
let
  hyprConfig = pkgs.writeText "nullshell-test-hyprland.lua" ''
    hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true } })
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
    hl.on("hyprland.start", function()
      hl.exec_cmd("${packages.desktop}/bin/nullshell session-start")
    end)
  '';
in
pkgs.testers.runNixOSTest {
  name = "nullshell-hyprland-session";
  nodes.machine = { ... }: {
    imports = [ ../nixos.nix ];
    programs.nullshell.enable = true;
    security.polkit.enablePkexecWrapper = true;
    programs.hyprland.enable = true;
    programs.hyprland.withUWSM = true;
    hardware.graphics.enable = true;
    virtualisation.memorySize = 3072;
    virtualisation.cores = 2;
    virtualisation.qemu.options = [
      "-vga none"
      "-device virtio-gpu-pci"
    ];
    users.users.preview = {
      isNormalUser = true;
      extraGroups = [
        "video"
        "input"
        "wheel"
      ];
      password = "test-only-password";
    };
    services.getty.autologinUser = "preview";
    environment.systemPackages = [
      packages.desktop
      pkgs.wtype
      pkgs.polkit
    ];
    systemd.packages = [
      packages.desktop
      pkgs.darkman
    ];
    environment.etc."xdg/darkman/config.yaml".text = ''
      lat: 31.2
      lng: 121.5
      usegeoclue: false
    '';
    fonts.packages = [ pkgs.dejavu_fonts ];
    programs.bash.loginShellInit = ''
      if [ "$(tty)" = /dev/tty1 ]; then
        mkdir -p "$HOME/.local/state/quickshell"
        printf 'true\n' > "$HOME/.local/state/quickshell/keep-awake"
        export LIBGL_ALWAYS_SOFTWARE=1 QT_QUICK_BACKEND=software XDG_CURRENT_DESKTOP=Hyprland
        exec Hyprland --config ${hyprConfig} > "$HOME/compositor.log" 2>&1
      fi
    '';
  };
  testScript = ''
    import json
    import shlex
    from datetime import timedelta

    machine.start()
    machine.wait_for_unit("multi-user.target")
    try:
        machine.wait_until_succeeds("test -S /run/user/1000/wayland-1", timeout=timedelta(seconds=30))
    except Exception:
        print(machine.succeed("cat /home/preview/compositor.log"))
        raise
    def user(command):
        return "su -s /bin/sh preview -c " + shlex.quote(
            "export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1; " + command
        )
    idle = user("nullshell ipc call idle status")
    machine.wait_until_succeeds(idle + " | grep '\"ready\":true'", timeout=timedelta(seconds=45))
    assert json.loads(machine.succeed(idle))["keepAwake"]
    appearance = user("nullshell ipc call appearance status")
    machine.wait_until_succeeds(appearance + " | grep '\"available\":true'", timeout=timedelta(seconds=30))
    polkit = user("nullshell ipc polkit call polkit status")
    machine.wait_until_succeeds(polkit + " | grep '\"registered\":true'", timeout=timedelta(seconds=30))
    machine.succeed(user("nullshell ipc call launcher toggle"))
    machine.succeed(user("nullshell ipc call launcher close"))
    wallpaper = user("nullshell ipc call wallpaper status")
    initial_screens = len(json.loads(machine.succeed(wallpaper))["screens"])
    signature = machine.succeed(user("systemctl --user show-environment | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p'")).strip()
    hyprctl = "HYPRLAND_INSTANCE_SIGNATURE=" + shlex.quote(signature) + " hyprctl "
    machine.succeed(user(hyprctl + "output create headless NULLSHELL-TEST"))
    machine.wait_until_succeeds(wallpaper + " | grep NULLSHELL-TEST", timeout=timedelta(seconds=15))
    assert len(json.loads(machine.succeed(wallpaper))["screens"]) == initial_screens + 1
    machine.succeed(user(hyprctl + "output remove NULLSHELL-TEST"))
    machine.wait_until_fails(wallpaper + " | grep NULLSHELL-TEST", timeout=timedelta(seconds=15))
    assert len(json.loads(machine.succeed(wallpaper))["screens"]) == initial_screens
    locker_pid = machine.succeed(user("systemctl --user show nullshell-lock -p MainPID --value")).strip()
    polkit_pid = machine.succeed(user("systemctl --user show nullshell-polkit -p MainPID --value")).strip()
    def auth_request(unit):
        command = "/run/wrappers/bin/pkexec /run/current-system/sw/bin/id -u > /home/preview/polkit-result"
        machine.succeed(user("systemd-run --user --collect --unit=" + unit + " /bin/sh -c " + shlex.quote(command)))

    auth_request("nullshell-auth-cancel")
    machine.wait_until_succeeds(polkit + " | grep '\"active\":true'", timeout=timedelta(seconds=15))
    machine.succeed(user("wtype -s 200 -k Escape"))
    machine.wait_until_succeeds(polkit + " | grep '\"active\":false'", timeout=timedelta(seconds=15))
    machine.fail("test -s /home/preview/polkit-result")
    auth_request("nullshell-auth-accept")
    machine.wait_until_succeeds(polkit + " | grep '\"active\":true'", timeout=timedelta(seconds=15))
    # Restarting desktop UI must preserve an in-progress authentication flow.
    machine.succeed(user("systemctl --user restart nullshell"))
    machine.wait_until_succeeds(idle + " | grep '\"ready\":true'", timeout=timedelta(seconds=30))
    assert json.loads(machine.succeed(idle))["keepAwake"]
    assert machine.succeed(user("systemctl --user show nullshell-lock -p MainPID --value")).strip() == locker_pid
    assert machine.succeed(user("systemctl --user show nullshell-polkit -p MainPID --value")).strip() == polkit_pid
    assert json.loads(machine.succeed(polkit))["active"]
    machine.succeed(user("wtype -s 200 -M ctrl -k a -m ctrl test-only-password -k Return"))
    machine.wait_until_succeeds("grep -qx 0 /home/preview/polkit-result", timeout=timedelta(seconds=15))
    machine.wait_until_succeeds(polkit + " | grep '\"active\":false'", timeout=timedelta(seconds=15))
    # Ending the owning session target tears down its components.
    machine.succeed(user("systemctl --user stop nullshell-session.target"))
    machine.fail(user("systemctl --user is-active nullshell.service"))
    machine.fail(user("systemctl --user is-active nullshell-polkit.service"))
  '';
}

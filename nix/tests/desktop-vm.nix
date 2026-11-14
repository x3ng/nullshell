{ pkgs, packages }:
let
  hyprConfig = pkgs.writeText "nullshell-test-hyprland.lua" ''
    hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true } })
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
    hl.on("hyprland.start", function()
      hl.exec_cmd("${packages.desktop}/bin/nullshell locker --no-duplicate")
      hl.exec_cmd("${packages.desktop}/bin/nullshell polkit --no-duplicate")
      hl.exec_cmd("${packages.desktop}/bin/nullshell desktop --no-duplicate")
      hl.exec_cmd("${packages.desktop}/bin/nullshell sleep-bridge")
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
      pkgs.quickshell
      pkgs.python3
      pkgs.grim
      pkgs.polkit
    ];
    programs.dconf.enable = true;
    xdg.portal.enable = true;
    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    xdg.portal.config.hyprland."org.freedesktop.impl.portal.Settings" = [ "gtk" ];
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
            "export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 QT_QUICK_BACKEND=software; " + command
        )
    idle = user("nullshell ipc call idle status")
    machine.wait_until_succeeds(idle + " | grep '\"ready\":true'", timeout=timedelta(seconds=45))
    assert json.loads(machine.succeed(idle))["keepAwake"]
    appearance = user("nullshell ipc call appearance status")
    machine.wait_until_succeeds(appearance + " | grep '\"available\":true'", timeout=timedelta(seconds=30))
    # The published application preference must follow manual changes, without darkman.
    portal = user("busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop org.freedesktop.portal.Settings Read ss org.freedesktop.appearance color-scheme")
    for mode, value in [("light", 2), ("dark", 1)]:
        machine.succeed(user("nullshell ipc call appearance setMode " + mode))
        machine.wait_until_succeeds(portal + " | grep 'u " + str(value) + "'", timeout=timedelta(seconds=30))
        assert json.loads(machine.succeed(appearance))["mode"] == mode
        assert machine.succeed("cat /home/preview/.local/state/nullshell/appearance-mode").strip() == mode
    polkit = user("nullshell ipc polkit call polkit status")
    machine.wait_until_succeeds(polkit + " | grep '\"registered\":true'", timeout=timedelta(seconds=30))
    machine.succeed(user("nullshell ipc call launcher toggle"))
    machine.succeed(user("nullshell ipc call launcher close"))
    wallpaper = user("nullshell ipc call wallpaper status")
    initial_screens = len(json.loads(machine.succeed(wallpaper))["screens"])
    compositor = json.loads(machine.succeed(user("hyprctl instances -j")))[0]
    signature = compositor["instance"]
    hyprctl = "HYPRLAND_INSTANCE_SIGNATURE=" + shlex.quote(signature) + " hyprctl "
    def shell_pid(entry):
        instances = json.loads(machine.succeed(user("quickshell list --all --json")))
        return next(str(instance["pid"]) for instance in instances
                    if instance["config_path"] == "${packages.assets}/share/nullshell/" + entry)
    # Preview the actual panel without replacing any of the desktop owners.
    desktop_pid = shell_pid("shell.qml")
    machine.succeed(user("nullshell desktop --daemonize --no-duplicate"))
    assert shell_pid("shell.qml") == desktop_pid
    machine.succeed(user("nullshell preview-panel > /home/preview/panel-preview.log 2>&1 &"))
    preview = "${pkgs.quickshell}/bin/quickshell ipc -p ${packages.assets}/share/nullshell/preview-panel.qml call preview"
    def preview_call(method):
        return machine.succeed(user(preview + " " + method))
    machine.wait_until_succeeds(user(preview + " status") + " | grep '\"open\":true'", timeout=timedelta(seconds=20))
    machine.wait_until_succeeds(user(hyprctl + "layers -j") + " | grep nullshell-preview-panel", timeout=timedelta(seconds=10))
    preview_call("quit")
    machine.wait_until_fails(user(preview + " status"), timeout=timedelta(seconds=10))
    machine.succeed(user("python3 ${../../tests/test_panel_preview.py} --qml ${packages.assets}/share/nullshell/preview-panel.qml --keyboard --screenshots /home/preview/panel-screenshots"))
    machine.copy_from_machine("/home/preview/panel-screenshots", "panel-preview")
    assert json.loads(machine.succeed(idle))["keepAwake"]
    assert shell_pid("shell.qml") == desktop_pid
    # Ordinary preview windows must really map; an offscreen load is not enough.
    for mode, title in [("greeter", "Greeter preview"), ("lock", "Lock screen preview"), ("polkit", "Authentication preview")]:
        machine.succeed(user("nullshell preview-" + mode + " > /home/preview/" + mode + "-preview.log 2>&1 & echo $! > /home/preview/preview.pid"))
        machine.wait_until_succeeds(user(hyprctl + "clients -j") + " | grep '" + title + "'", timeout=timedelta(seconds=15))
        machine.succeed(user("kill $(cat /home/preview/preview.pid)"))
    machine.succeed(user(hyprctl + "output create headless NULLSHELL-TEST"))
    machine.wait_until_succeeds(wallpaper + " | grep NULLSHELL-TEST", timeout=timedelta(seconds=15))
    assert len(json.loads(machine.succeed(wallpaper))["screens"]) == initial_screens + 1
    machine.succeed(user(hyprctl + "output remove NULLSHELL-TEST"))
    machine.wait_until_fails(wallpaper + " | grep NULLSHELL-TEST", timeout=timedelta(seconds=15))
    assert len(json.loads(machine.succeed(wallpaper))["screens"]) == initial_screens
    locker_pid = shell_pid("lock/shell.qml")
    polkit_pid = shell_pid("polkit/shell.qml")
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
    machine.succeed(user("kill " + desktop_pid))
    machine.wait_until_fails(idle, timeout=timedelta(seconds=10))
    machine.sleep(3)
    machine.fail(idle)
    # No supervisor: it stays stopped until explicitly started again.
    machine.succeed(user("nullshell desktop --daemonize --no-duplicate"))
    machine.wait_until_succeeds(idle + " | grep '\"ready\":true'", timeout=timedelta(seconds=30))
    assert json.loads(machine.succeed(idle))["keepAwake"]
    assert shell_pid("lock/shell.qml") == locker_pid
    assert shell_pid("polkit/shell.qml") == polkit_pid
    assert json.loads(machine.succeed(polkit))["active"]
    machine.succeed(user("wtype -s 200 -M ctrl -k a -m ctrl test-only-password -k Return"))
    machine.wait_until_succeeds("grep -qx 0 /home/preview/polkit-result", timeout=timedelta(seconds=15))
    machine.wait_until_succeeds(polkit + " | grep '\"active\":false'", timeout=timedelta(seconds=15))
    # Direct clients must exit when their compositor disappears, without units.
    desktop_pid = shell_pid("shell.qml")
    machine.succeed(user("kill " + str(compositor["pid"])))
    for pid in [desktop_pid, locker_pid, polkit_pid]:
        machine.wait_until_fails("test -d /proc/" + pid, timeout=timedelta(seconds=20))
    machine.succeed("test ! -d ${packages.desktop}/lib/systemd/user")
  '';
}

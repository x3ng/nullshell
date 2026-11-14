{ pkgs, packages }:
let
  session = pkgs.writeShellScript "nullshell-test-session" ''
    id -un > "$HOME/authenticated-session"
    exec ${pkgs.coreutils}/bin/sleep 60
  '';
  sessions = pkgs.writeTextDir "share/wayland-sessions/nullshell-test.desktop" ''
    [Desktop Entry]
    Name=Nullshell test session
    Type=Application
    Exec=${session}
  '';
  alternative = pkgs.writeText "nullshell-alternative.desktop" ''
    [Desktop Entry]
    Name=Alternative session
    Type=Application
    Exec=${pkgs.coreutils}/bin/false
  '';
  startGreeter = pkgs.writeShellScript "nullshell-test-greeter" ''
    umask 077
    exec > /run/nullshell-greeter-test/greeter.log 2>&1
    export XDG_RUNTIME_DIR=/run/nullshell-greeter-test
    export NULLSHELL_GREETER_OVERRIDE_DIR=/var/lib/test-greeter-ui
    export NULLSHELL_APPEARANCE_FILE=/var/lib/test-relocated-theme/theme.json
    export NULLSHELL_WALLPAPER_FILE=/var/lib/test-relocated-theme/wallpaper.json
    export NULLSHELL_GREETER_STATE_FILE=/var/lib/nullshell-greeter/last-login.json
    export XDG_DATA_DIRS=/run/nullshell-greeter-test/sessions/share
    mkdir -p "$XDG_DATA_DIRS/wayland-sessions"
    cp ${sessions}/share/wayland-sessions/nullshell-test.desktop "$XDG_DATA_DIRS/wayland-sessions/"
    export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
    export QT_QUICK_BACKEND=software
    exec ${pkgs.dbus}/bin/dbus-run-session --dbus-daemon=${pkgs.dbus}/bin/dbus-daemon -- \
      ${pkgs.cage}/bin/cage -s -- ${packages.greeter}/bin/nullshell-greeter
  '';
in
pkgs.testers.runNixOSTest {
  name = "nullshell-greetd-authentication";
  nodes.machine = { lib, ... }: {
    imports = [ ../nixos.nix ];
    programs.nullshell.greeter = {
      enable = true;
      interfaceDirectory = "/var/lib/test-greeter-ui";
      appearance.sourceUser = "preview";
      appearance.directory = "/var/lib/test-relocated-theme";
    };
    services.greetd.settings.default_session.command = lib.mkForce "${startGreeter}";
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
    users.users.preview = {
      isNormalUser = true;
      password = "test-only-password";
    };
    users.users.unrelated.isNormalUser = true;
    environment.systemPackages = [
      pkgs.wtype
      packages.helper
    ];
    fonts.packages = [ pkgs.dejavu_fonts ];
    systemd.tmpfiles.rules = [ "d /run/nullshell-greeter-test 0700 greeter greeter -" ];
  };
  testScript = ''
    import shlex
    import json
    from datetime import timedelta

    machine.start()
    machine.wait_for_unit("greetd.service")
    machine.wait_until_succeeds("test -S /run/nullshell-greeter-test/wayland-0", timeout=timedelta(seconds=30))
    try:
        machine.wait_until_succeeds("grep 'Configuration Loaded' /run/nullshell-greeter-test/greeter.log", timeout=timedelta(seconds=30))
    except Exception:
        print(machine.succeed("cat /run/nullshell-greeter-test/greeter.log"))
        raise
    # Export as the selected ordinary user, including under a private umask.
    colors = dict.fromkeys("backdrop panelSurface backgroundSurface surfaceRaised surfaceHover surfaceSelected materialEdge materialShadow wallpaperScrim inputSurface outline separator textPrimary textSecondary textMuted accent accentInk danger accentWarm".split(), "#eeeeee")
    snapshot = json.dumps(dict(version=1, mode="light", colors=colors))
    def export_theme():
        command = "umask 077; printf %s " + shlex.quote(snapshot) + " | nullshell-helper appearance-export /var/lib/test-relocated-theme/theme.json"
        machine.succeed("su -s /bin/sh preview -c " + shlex.quote(command))
    export_theme()
    assert machine.succeed("stat -c '%U %G %a' /var/lib/test-relocated-theme/theme.json").strip() == "preview greeter 640"
    machine.succeed("su -s /bin/sh greeter -c 'cat /var/lib/test-relocated-theme/theme.json'")
    machine.fail("su -s /bin/sh greeter -c 'test -w /var/lib/test-relocated-theme'")
    machine.fail("su -s /bin/sh unrelated -c 'cat /var/lib/test-relocated-theme/theme.json'")
    machine.fail("su -s /bin/sh preview -c 'test -w /var/lib/nullshell-greeter'")
    def type_into_greeter(arguments):
        machine.succeed("su -s /bin/sh greeter -c " + shlex.quote(
            "XDG_RUNTIME_DIR=/run/nullshell-greeter-test WAYLAND_DISPLAY=wayland-0 wtype " + arguments
        ))

    type_into_greeter("-s 200 -M ctrl -k a -m ctrl preview -k Return -s 200 wrong-password -k Return")
    machine.wait_until_succeeds("journalctl -u greetd | grep 'authentication failure'", timeout=timedelta(seconds=15))
    machine.sleep(3)
    machine.fail("test -f /home/preview/authenticated-session")
    # Appearance updates during an authentication conversation must preserve it.
    snapshot = json.dumps(dict(version=1, mode="dark", colors={key: "#222222" for key in colors}))
    export_theme()
    type_into_greeter("-s 200 -M ctrl -k a -m ctrl test-only-password -k Return")
    machine.wait_for_file("/home/preview/authenticated-session", timeout=timedelta(seconds=30))
    assert machine.succeed("cat /home/preview/authenticated-session").strip() == "preview"
    assert machine.succeed("stat -c %U /home/preview/authenticated-session").strip() == "preview"
    machine.wait_until_succeeds("test -f /var/lib/nullshell-greeter/last-login.json", timeout=timedelta(seconds=15))
    saved = machine.succeed("cat /var/lib/nullshell-greeter/last-login.json")
    assert '"user":"preview"' in saved
    assert '"session":"nullshell-test.desktop"' in saved
    assert machine.succeed("stat -c '%U %a' /var/lib/nullshell-greeter/last-login.json").strip() == "greeter 600"

    machine.fail("su -s /bin/sh greeter -c 'nullshell-install-greeter --reset'")
    # Install code independently of both the package and mutable theme data.
    # No desktop/Git/HOME state is accepted into the administrative snapshot.
    machine.succeed("mkdir -p /root/greeter-work")
    machine.succeed("cp -R ${packages.assets}/share/nullshell/. /root/greeter-work/")
    machine.succeed("chmod -R u+w /root/greeter-work")
    machine.succeed("mkdir -p /root/greeter-work/.git /root/greeter-work/runtime-state")
    machine.succeed("touch /root/greeter-work/.git/private /root/greeter-work/runtime-state/private")
    machine.succeed("nullshell-install-greeter --source /root/greeter-work")
    first = machine.succeed("readlink -f /var/lib/test-greeter-ui/current").strip()
    machine.fail("test -e " + first + "/.git")
    machine.fail("test -e " + first + "/runtime-state")
    assert machine.succeed("stat -c '%U %G %a' " + first + "/greeter.qml").strip() == "root root 644"
    machine.fail("su -s /bin/sh greeter -c 'test -w " + first + "'")
    # Reject unsupported resource contracts without changing the active pointer.
    machine.succeed("printf %s 99 > /root/greeter-work/greeter-interface.version")
    machine.fail("nullshell-install-greeter --source /root/greeter-work")
    assert machine.succeed("readlink -f /var/lib/test-greeter-ui/current").strip() == first
    machine.succeed("printf %s 1 > /root/greeter-work/greeter-interface.version")
    machine.succeed("ln -s /etc/passwd /root/greeter-work/Injected.qml")
    machine.fail("nullshell-install-greeter --source /root/greeter-work")
    assert machine.succeed("readlink -f /var/lib/test-greeter-ui/current").strip() == first
    machine.succeed("rm /root/greeter-work/Injected.qml")

    # A newly available alphabetically first session must not replace the saved choice.
    machine.succeed("cp ${alternative} /run/nullshell-greeter-test/sessions/share/wayland-sessions/alternative.desktop")
    machine.succeed("systemctl restart greetd.service")
    machine.wait_until_succeeds("test -S /run/nullshell-greeter-test/wayland-0", timeout=timedelta(seconds=30))
    machine.sleep(2)
    machine.succeed("rm /home/preview/authenticated-session")
    machine.wait_until_succeeds("grep 'Launching config:.*test-greeter-ui/.qml.' /run/nullshell-greeter-test/greeter.log", timeout=timedelta(seconds=15))
    # Updates never restart the greeter, and its pinned QML remains available.
    pid = machine.succeed("pgrep -u greeter -f 'quickshell.*greeter.qml' | head -1").strip()
    machine.succeed("nullshell-install-greeter --source /root/greeter-work")
    second = machine.succeed("readlink -f /var/lib/test-greeter-ui/current").strip()
    assert first != second
    machine.succeed("test -f " + first + "/greeter.qml")
    assert machine.succeed("pgrep -u greeter -f 'quickshell.*greeter.qml' | head -1").strip() == pid
    # Only a password is typed: a second login proves the user and session were restored.
    type_into_greeter("-s 200 test-only-password -k Return")
    machine.wait_for_file("/home/preview/authenticated-session", timeout=timedelta(seconds=30))
    machine.succeed("nullshell-install-greeter --reset")
    machine.fail("test -e /var/lib/test-greeter-ui/current")
    machine.fail("test -d " + first)
    machine.fail("test -d " + second)
    # Reset is explicit; the package is selected on the next launch, without reinstall.
    machine.succeed("systemctl restart greetd.service")
    machine.wait_until_succeeds("grep 'Launching config:.*nix/store' /run/nullshell-greeter-test/greeter.log", timeout=timedelta(seconds=15))
  '';
}

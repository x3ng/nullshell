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
    programs.nullshell.greeter.enable = true;
    services.greetd.settings.default_session.command = lib.mkForce "${startGreeter}";
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
    users.users.preview = {
      isNormalUser = true;
      password = "test-only-password";
    };
    environment.systemPackages = [ pkgs.wtype ];
    fonts.packages = [ pkgs.dejavu_fonts ];
    systemd.tmpfiles.rules = [ "d /run/nullshell-greeter-test 0700 greeter greeter -" ];
  };
  testScript = ''
    import shlex
    from datetime import timedelta

    machine.start()
    machine.wait_for_unit("greetd.service")
    machine.wait_until_succeeds("test -S /run/nullshell-greeter-test/wayland-0", timeout=timedelta(seconds=30))
    machine.wait_until_succeeds("grep 'Configuration Loaded' /run/nullshell-greeter-test/greeter.log", timeout=timedelta(seconds=30))
    def type_into_greeter(arguments):
        machine.succeed("su -s /bin/sh greeter -c " + shlex.quote(
            "XDG_RUNTIME_DIR=/run/nullshell-greeter-test WAYLAND_DISPLAY=wayland-0 wtype " + arguments
        ))

    type_into_greeter("-s 200 -M ctrl -k a -m ctrl preview -k Return -s 200 wrong-password -k Return")
    machine.wait_until_succeeds("journalctl -u greetd | grep 'authentication failure'", timeout=timedelta(seconds=15))
    machine.sleep(3)
    machine.fail("test -f /home/preview/authenticated-session")
    type_into_greeter("-s 200 -M ctrl -k a -m ctrl test-only-password -k Return")
    machine.wait_for_file("/home/preview/authenticated-session", timeout=timedelta(seconds=30))
    assert machine.succeed("cat /home/preview/authenticated-session").strip() == "preview"
    assert machine.succeed("stat -c %U /home/preview/authenticated-session").strip() == "preview"
    machine.wait_until_succeeds("test -f /var/lib/nullshell-greeter/last-login.json", timeout=timedelta(seconds=15))
    saved = machine.succeed("cat /var/lib/nullshell-greeter/last-login.json")
    assert '"user":"preview"' in saved
    assert '"session":"nullshell-test.desktop"' in saved
    assert machine.succeed("stat -c '%U %a' /var/lib/nullshell-greeter/last-login.json").strip() == "greeter 600"

    # A newly available alphabetically first session must not replace the saved choice.
    machine.succeed("cp ${alternative} /run/nullshell-greeter-test/sessions/share/wayland-sessions/alternative.desktop")
    machine.succeed("systemctl restart greetd.service")
    machine.wait_until_succeeds("test -S /run/nullshell-greeter-test/wayland-0", timeout=timedelta(seconds=30))
    machine.sleep(2)
    machine.succeed("rm /home/preview/authenticated-session")
    # Only a password is typed: a second login proves the user and session were restored.
    type_into_greeter("-s 200 test-only-password -k Return")
    machine.wait_for_file("/home/preview/authenticated-session", timeout=timedelta(seconds=30))
  '';
}

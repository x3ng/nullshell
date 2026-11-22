"""Portable Wayland preview checks. No Nix imports or host service changes.

Requires Python 3 and Quickshell on PATH and a running Wayland compositor.
Optional --keyboard uses wtype; --screenshots captures only the preview card. Prefer a nested/test
compositor for keyboard injection. The process started here is always cleaned up.
"""
import argparse
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import time
import zlib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qml", type=Path, default=Path(__file__).resolve().parents[1] / "preview-panel.qml")
    parser.add_argument("--screenshots", type=Path)
    parser.add_argument("--keyboard", action="store_true")
    only = parser.add_mutually_exclusive_group()
    only.add_argument("--appearance-only", action="store_true", help="Check only the appearance page")
    only.add_argument("--displays-only", action="store_true", help="Check only the display layout page")
    only.add_argument("--idle-only", action="store_true", help="Check only the idle settings page")
    args = parser.parse_args()
    if not os.environ.get("WAYLAND_DISPLAY"):
        parser.error("A Wayland session is required; no Nix environment is required")
    entry = str(args.qml.resolve(strict=True))
    ipc = ["quickshell", "ipc", "--path", entry, "call", "preview"]
    existing = subprocess.run(ipc + ["status"], capture_output=True, timeout=3)
    if existing.returncode == 0:
        parser.error("This source preview is already running; close it before running the test")
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)

    def call(*arguments):
        return subprocess.check_output(ipc + list(arguments), text=True, timeout=5).strip()

    def state():
        return json.loads(call("status"))

    def settle():
        previous = None
        for _ in range(30):
            value = state()
            geometry = value["card"]
            if geometry == previous and geometry["height"] > 0:
                time.sleep(0.3)
                return state()
            previous = geometry
            time.sleep(0.25)
        raise AssertionError("Panel geometry did not settle")

    def screenshot(name):
        if args.screenshots:
            path = args.screenshots / (name + ".png")
            assert call("capture", str(path)) == "true"
            # grabToImage returns before PNG encoding completes. A nonempty
            # file is not a completion signal; require a fully decoded image.
            from PIL import Image
            decoded = None
            for _ in range(50):
                try:
                    with Image.open(path) as image:
                        image.load()
                        decoded = image.convert("RGB")
                    break
                except (OSError, ValueError):
                    time.sleep(.1)
            assert decoded is not None, "Preview capture did not finish encoding"
            if name.startswith("appearance-"):
                body = decoded.crop((20, 70, decoded.width - 20, decoded.height - 20))
                colors = body.getcolors(body.width * body.height)
                assert max(count for count, _ in colors) < body.width * body.height * .99, "Appearance content was not rendered"

    def check_appearance():
        # Enter appearance through the brightness row's production button.
        call("page", "overview")
        settle()
        assert call("activateControl", "brightness-details") == "true"
        assert settle()["page"] == "detail:appearance"
        for mode in ["light", "dark", "auto"]:
            assert call("activateControl", "appearance-mode-" + mode) == "true"
            assert settle()["appearanceMode"] == mode
        assert call("activateControl", "appearance-timezone-location") == "true"
        assert settle()["appearanceSettings"]["location"] == "timezone"
        assert call("activateControl", "appearance-ip-location") == "true"
        assert settle()["appearanceSettings"]["location"] == "ip"
        assert call("activateControl", "appearance-fixed-location") == "true"
        settle()
        call("coordinate", "latitude", "91")
        call("coordinate", "longitude", "0")
        call("activateControl", "appearance-apply-location")
        assert state()["appearanceSettings"]["location"] != "fixed"
        call("coordinate", "latitude", "51.5")
        call("coordinate", "longitude", "-0.1")
        call("activateControl", "appearance-apply-location")
        assert state()["appearanceSettings"]["latitude"] == 51.5
        for width in ["740", "440"]:
            call("width", width)
            for light in ["false", "true"]:
                call("light", light)
                for scenario in ["timezone", "fixed", "locating", "unavailable", "override"]:
                    call("appearanceState", scenario)
                    current = settle()
                    geometry = json.loads(call("detailGeometry", "appearance"))
                    # Short pages must not create a spurious scroll range or scrollbar.
                    assert current["card"]["height"] < 700, current
                    assert geometry["contentHeight"] <= geometry["viewportHeight"] + 1, geometry
                    screenshot("appearance-" + width + "-" + light + "-" + scenario)
        call("appearanceState", "override")
        settle()
        assert call("activateControl", "appearance-resume") == "true", state()
        assert state()["overrideUntil"] == 0
        call("activateControl", "appearance-reset")
        assert not state()["preferencesOverridden"]

    def finish(process, log):
        call("quit")
        process.wait(timeout=5)
        assert process.returncode == 0
        errors = re.findall(r"^.*(?:TypeError|ReferenceError|SyntaxError|Cannot assign|not a function|failed to load|Binding loop|Cannot anchor).*$", log.read_text(), re.MULTILINE | re.IGNORECASE)
        assert not errors, "\n".join(errors)

    def check_displays():
        call("page", "displays")
        assert settle()["page"] == "detail:displays"
        assert call("activateControl", "displays-test") == "false", "A clean layout needs no trial"
        for width, light in [("740", "true"), ("740", "false"), ("440", "true"), ("440", "false")]:
            call("width", width)
            call("light", light)
            s = settle()
            button = json.loads(call("controlBounds", "displays-test"))
            assert button["height"] >= 32 and button["y"] + button["height"] <= s["card"]["bottom"] - 8, (s, button)
            geometry = json.loads(call("detailGeometry", "displays"))
            assert geometry["contentHeight"] <= geometry["viewportHeight"] + 1, geometry
            screenshot("displays-editor-" + width + ("-light" if light == "true" else "-dark"))
        assert call("activateControl", "displays-enabled") == "true"
        assert call("displaySelect", "1") == "true"
        assert call("activateControl", "displays-enabled") == "true"
        assert call("activateControl", "displays-test") == "false", "Cannot disable all displays"
        assert call("activateControl", "displays-enabled") == "true"
        assert call("displaySelect", "0") == "true"
        assert call("activateControl", "displays-enabled") == "true"
        assert call("displayValue", "mode", "1280x720@60Hz") == "true"
        assert call("displayValue", "x", "-80") == "true"
        if args.keyboard:
            assert call("focusControl", "displays", "displays-scale") == "true"
            subprocess.run(["wtype", "-M", "ctrl", "-k", "a", "-m", "ctrl", "1.25"], check=True, timeout=5)
        else:
            assert call("displayValue", "scale", "1.25") == "true"
        screenshot("displays-unsaved")
        assert call("activateControl", "displays-test") == "true"
        s = settle()
        assert s["displayPhase"] == "preview"
        assert (s["displayDraft"][0]["width"], s["displayDraft"][0]["scale"], s["displayDraft"][0]["x"]) == (1280, 1.25, -80), s
        assert s["displayTrialChanges"][0]["name"] == "eDP-1"
        changes = {row["label"]: row["value"] for row in s["displayTrialChanges"][0]["rows"]}
        assert changes == {"Resolution": "1920 × 1080 → 1280 × 720", "Scale": "1× → 1.25×", "Position": "-80, 0"}, changes
        for control in ("displays-confirm", "displays-revert"):
            button = json.loads(call("controlBounds", control))
            assert button["width"] >= 90 and button["y"] + button["height"] <= s["card"]["bottom"] - 8, button
        screenshot("displays-confirmation")
        if args.keyboard:
            assert call("focusControl", "displays", "displays-confirm") == "true"
            assert state()["focusedItem"] == "displays-confirm"
            screenshot("displays-confirmation-focus")
            subprocess.run(["wtype", "-k", "Return"], check=True, timeout=5)
        else:
            assert call("activateControl", "displays-confirm") == "true"
        assert settle()["lastAction"] == "display-confirm"
        assert call("activateControl", "displays-test") == "false"
        assert call("displayValue", "scale", "1.5") == "true"
        assert call("activateControl", "displays-test") == "true"
        settle()
        assert call("activateControl", "displays-revert") == "true"
        assert settle()["lastAction"] == "display-revert"
        screenshot("displays-reverted")

    def check_idle():
        call("page", "session")
        settle()
        assert call("activateControl", "power-idle-settings") == "true"
        s = settle()
        assert s["page"] == "detail:idle" and s["idleFields"] == {"dim":"2:30", "lock":"5:00"}
        for width, light in [("740", "true"), ("740", "false"), ("440", "true"), ("440", "false")]:
            call("width", width)
            call("light", light)
            settle()
            screenshot("idle-" + width + ("-light" if light == "true" else "-dark"))
        assert call("idleValue", "lockSeconds", "1:61") == "true"
        assert call("activateControl", "idle-save") == "false"
        if args.keyboard:
            assert call("focusControl", "idle", "idle-lockSeconds") == "true"
            subprocess.run(["wtype", "-M", "ctrl", "-k", "a", "-m", "ctrl", "1:40"], check=True, timeout=5)
        else:
            assert call("idleValue", "lockSeconds", "1:40") == "true"
        call("idleReloadUnchanged")
        assert call("activateControl", "idle-save") == "false"
        assert call("idleValue", "dimSeconds", "60") == "true"
        screenshot("idle-unsaved")
        assert call("activateControl", "idle-save") == "true"
        s = settle()
        assert s["idleOverridden"] and s["idleTimers"]["lockSeconds"] == 100
        assert call("activateControl", "idle-reset") == "true"
        s = settle()
        assert not s["idleOverridden"] and s["idleTimers"]["lockSeconds"] == 300
        before = s["keepAwake"]
        assert call("activateControl", "idle-keep-awake") == "true"
        assert settle()["keepAwake"] != before
        screenshot("idle-active")
        assert call("activateControl", "idle-keep-awake") == "true"
        assert settle()["keepAwake"] == before

    with tempfile.TemporaryDirectory(prefix="nullshell-preview-test-") as temporary:
        # Synthetic solid-color image; no personal wallpaper enters the fixture.
        def png_chunk(kind, data):
            return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))
        wallpaper_image = Path(temporary) / "synthetic-wallpaper.png"
        wallpaper_image.write_bytes(b"\x89PNG\r\n\x1a\n"
            + png_chunk(b"IHDR", struct.pack("!2I5B", 64, 48, 8, 2, 0, 0, 0))
            + png_chunk(b"IDAT", zlib.compress((b"\0" + bytes((50, 95, 135)) * 64) * 48))
            + png_chunk(b"IEND", b""))
        log = Path(temporary) / "preview.log"
        with log.open("w") as output:
            process = subprocess.Popen(["quickshell", "--path", entry], stdout=output, stderr=output)
        try:
            for _ in range(100):
                if process.poll() is not None:
                    raise AssertionError("Preview exited during startup")
                probe = subprocess.run(ipc + ["status"], text=True, capture_output=True, timeout=3)
                if probe.returncode == 0 and json.loads(probe.stdout)["open"]:
                    break
                time.sleep(0.1)
            else:
                raise AssertionError("Preview IPC did not become ready")
            if args.appearance_only:
                check_appearance()
                finish(process, log)
                print("Appearance preview: modes, location controls, layout and cleanup passed")
                return
            if args.displays_only:
                check_displays()
                finish(process, log)
                print("Display editor preview: draft, test, confirmation, revert and cleanup passed")
                return
            if args.idle_only:
                check_idle()
                finish(process, log)
                print("Idle settings preview: input validation, save, reset, Keep awake and cleanup passed")
                return
            settle()
            screenshot("normal")
            # With only the tools remaining, resizing must still recenter them.
            call("scenario", "empty")
            for width in ["440", "740", "440"]:
                call("width", width)
                settle()
                footer = json.loads(call("footerGeometry"))
                assert abs(footer["toolsX"] - (footer["width"] - footer["toolsWidth"]) / 2) < 1, footer
            call("width", "740")
            call("scenario", "normal")
            # Simulate capability results without altering the host compositor.
            for light in ["false", "true"]:
                call("light", light)
                for blur in ["false", "true"]:
                    call("blur", blur)
                    material = settle()
                    assert material["blur"] == (blur == "true"), material
                    assert (material["materialOpacity"] < 1) == material["blur"], material
                    screenshot(("light" if light == "true" else "dark") + ("-glass" if blur == "true" else "-solid"))
            call("light", "false")
            for scenario in ["empty", "crowded", "media", "normal"]:
                assert call("scenario", scenario) == "true"
                for page in ["overview", "wifi", "bluetooth", "audio", "media", "notifications", "desktop", "appearance", "wallpaper"]:
                    call("page", page)
                    current = settle()
                    expected = page if page in ["overview", "desktop"] else "detail:" + page
                    assert current["page"] == expected and current["open"], current
                    assert current["card"]["width"] > 0
            for width in ["440", "740"]:
                call("width", width)
                for light in ["false", "true"]:
                    call("light", light)
                    call("page", "wifi")
                    settle()
                    assert call("activateControl", "wifi-device-Enterprise network") == "true"
                    settle()
                    assert call("activateControl", "wifi-connect") == "false"
                    screenshot("wifi-unsupported-" + width + "-" + light)
                    assert call("activateControl", "wifi-device-Guest network") == "true"
                    settle()
                    assert call("activateControl", "wifi-connect") == "true"
            call("scenario", "crowded")
            call("search", "terminal")
            before = settle()
            assert before["results"] > 0
            if args.keyboard:
                subprocess.run(["wtype", "-s", "200", "-M", "ctrl", "-k", "n", "-m", "ctrl"], check=True, timeout=5)
                before = state()
                assert before["selectedIndex"] == 1, before
            call("tick")
            changed = settle()
            assert changed["results"] == before["results"]
            assert changed["selectedKey"] == before["selectedKey"]
            for width, light in [("440", "true"), ("740", "false")]:
                call("width", width)
                call("light", light)
                call("page", "overview")
                call("page", "desktop")
                settle()
                assert call("activateControl", "desktop-shortcuts") == "true"
                settle()
                assert call("shortcutCount") == "2"
                screenshot("shortcuts-" + width)
                assert call("setToolField", "shortcut-filter", "terminal") == "true"
                assert call("shortcutCount") == "1"
            call("search", ">")
            assert settle()["results"] == 6
            for width in ["440", "740"]:
                call("width", width)
                for light in ["false", "true"]:
                    call("light", light)
                    for mode in ["all", "panel", "operation"]:
                        call("search", {"all": ">", "panel": ">?", "operation": ">!"}[mode])
                        filtered = settle()
                        assert filtered["commandFilter"] == mode
                        assert filtered["results"] == (6 if mode == "all" else 3)
                        assert filtered["selectedIndex"] == 0
                        if mode != "all": assert set(filtered["resultTypes"]) == {mode}
                        screenshot("commands-" + width + "-" + light + "-" + mode)
            call("search", ">")
            if args.keyboard:
                subprocess.run(["wtype", "?"], check=True, timeout=5)
                assert settle()["commandFilter"] == "panel"
                subprocess.run(["wtype", "-k", "BackSpace"], check=True, timeout=5)
                assert settle()["commandFilter"] == "all"
            call("search", "> power")
            assert settle()["results"] == 2
            call("activateControl", "command-filter-operation")
            assert settle()["results"] == 1
            assert state()["query"] == ">! power"
            call("activateControl", "command-filter-panel")
            assert settle()["results"] == 1 and state()["query"] == ">? power"
            call("activateControl", "command-filter-all")
            assert settle()["results"] == 2 and state()["query"] == "> power"
            call("search", ">!power")
            assert settle()["results"] == 1
            call("activateSelected")
            assert state()["lastAction"] == "activate power:balanced"
            assert state()["commandFilter"] == "all"
            call("search", "> keyboard")
            settle()
            previous = state()["lastAction"]
            call("activateSelected")
            assert state()["lastAction"] == previous and state()["query"] == "> keyboard"
            screenshot("commands-unavailable")
            call("activateControl", "command-filter-panel")
            assert settle()["results"] == 0
            screenshot("commands-empty")
            call("search", "terminal")
            assert settle()["commandFilter"] == "all"
            call("search", ">")
            call("activateControl", "command-filter-panel")
            call("close")
            call("openPanel")
            call("search", ">")
            assert settle()["commandFilter"] == "all"
            call("action", "keep-awake")
            assert not state()["keepAwake"]
            call("width", "440")
            call("light", "true")
            call("page", "overview")
            narrow = settle()
            assert narrow["card"]["width"] == 440 and not narrow["dark"], narrow
            screenshot("narrow-light")
            # Focus-following must reveal controls below the overview viewport.
            if args.keyboard:
                call("page", "overview")
                call("scenario", "crowded")
                call("width", "440")
                call("scrollOverview", "false")
                settle()
                assert call("focusControl", "overview", "tray-item-5") == "true"
                focused = settle()
                assert focused["focusedItem"] == "tray-item-5", focused
                assert focused["focusY"] >= -1 and focused["focusY"] + focused["focusHeight"] <= focused["overviewHeight"] + 1, focused
                subprocess.run(["wtype", "-k", "Return"], check=True, timeout=5)
                assert state()["lastAction"] == "tray activated"
                # Tab continues from the tray to the session button without
                # losing focus outside the visible scroll area.
                subprocess.run(["wtype", "-k", "Tab"], check=True, timeout=5)
                focused = settle()
                assert focused["focusedItem"] == "power-menu-button", focused
                assert focused["focusY"] >= -1 and focused["focusY"] + focused["focusHeight"] <= focused["overviewHeight"] + 1, focused
                screenshot("overview-keyboard-focus")
            call("page", "notifications")
            for width in ["440", "740"]:
                call("width", width)
                for light in ["false", "true"]:
                    call("light", light)
                    call("activateControl", "notification-quiet")
                    assert settle()["doNotDisturb"]
                    screenshot("notifications-quiet-" + width + "-" + light)
                    call("activateControl", "notification-quiet")
                    assert not settle()["doNotDisturb"]
            call("page", "overview")
            # Quick toggles stay on the homepage; labelled arrows navigate.
            for section in ["wifi", "bluetooth"]:
                call("page", "overview")
                assert call("activateControl", "quick-" + section + "-toggle") == "true"
                assert state()["page"] == "overview"
                assert state()["lastAction"] == section + "-toggle"
                assert call("activateControl", "quick-" + section + "-details") == "true"
                assert state()["page"] == "detail:" + section
            call("page", "overview")
            for width in ["440", "740"]:
                call("width", width)
                for light in ["false", "true"]:
                    call("light", light)
                    settle()
                    screenshot("quick-controls-" + width + "-" + light)
                    call("scrollOverview", "true")
                    settle()
                    screenshot("quick-footer-" + width + "-" + light)
                    call("scrollOverview", "false")
            for condition in ["busy", "unavailable"]:
                call("quickState", condition)
                for section in ["wifi", "bluetooth"]:
                    assert call("activateControl", "quick-" + section + "-toggle") == "false"
                    assert call("activateControl", "quick-" + section + "-details") == "true"
                    call("page", "overview")
                settle()
                screenshot("quick-" + condition)
            call("quickState", "error")
            settle()
            screenshot("quick-error")
            call("quickState", "normal")
            check_appearance()
            check_displays()
            check_idle()
            # Opening the power menu and selecting destructive actions never
            # executes them until the explicit confirmation button is pressed.
            call("page", "overview")
            settle()
            assert call("activateControl", "power-menu-button") == "true"
            assert settle()["page"] == "detail:session"
            for width in ["740", "440"]:
                call("width", width)
                for light in ["false", "true"]:
                    call("light", light)
                    settle()
                    screenshot("power-" + width + "-" + light)
            assert call("setToolField", "awake-duration", "37") == "true"
            assert call("activateControl", "awake-duration-apply") == "true"
            settle()
            screenshot("session-timed-awake")
            assert call("activateControl", "awake-duration-apply") == "true"
            for action in ["logout", "reboot", "poweroff"]:
                previous = state()["lastAction"]
                assert call("activateControl", "power-action-" + action) == "true"
                assert state()["lastAction"] == previous
                settle()
                screenshot("power-confirm-" + action)
                assert call("activateControl", "power-cancel") == "true"
                assert state()["lastAction"] == previous
                call("activateControl", "power-action-" + action)
                assert call("activateControl", "power-confirm") == "true"
                assert state()["lastAction"] == "session:" + action
            call("sessionState", "error")
            settle()
            screenshot("power-error")
            for scenario in ["busy", "unavailable"]:
                call("sessionState", scenario)
                settle()
                assert call("activateControl", "power-action-poweroff") == "false"
                screenshot("power-" + scenario)
            call("sessionState", "normal")
            call("activateControl", "power-action-suspend")
            assert state()["lastAction"] == "session:suspend"
            call("activateControl", "power-action-poweroff")
            call("page", "overview")
            call("page", "session")
            settle()
            assert call("activateControl", "power-confirm") == "false"
            call("close")
            assert not state()["open"]
            call("openPanel")
            assert state()["open"]
            # Moving the same view preserves drafts, releases the overlay, and
            # keeps each feature unique while ordinary windows remain open.
            for light in ["false", "true"]:
                call("light", light)
                for width in ["440", "740"]:
                    call("width", width)
                    call("page", "wallpaper")
                    call("draft", "wallpaper", wallpaper_image.as_uri())
                    settle()
                    screenshot("wallpaper-" + width + "-" + light)
                    geometry = json.loads(call("detailGeometry", "wallpaper"))
                    assert abs(geometry["imageHeight"] - geometry["imageWidth"] * 9 / 16) < 1, geometry
                    assert state()["card"]["height"] <= 700, state()
            assert call("draft", "wallpaper", wallpaper_image.as_uri()) == "true"
            assert call("activateControl", "wallpaper-choose") == "true"
            time.sleep(.5)
            assert state()["dialogOpen"] and state()["open"]
            if args.screenshots and os.environ.get("NULLSHELL_PREVIEW_CAPTURE_DESKTOP") == "1":
                subprocess.run(["grim", str(args.screenshots / "wallpaper-file-dialog.png")], check=True, timeout=5)
            call("cancelFileDialog")
            assert not state()["dialogOpen"] and state()["wallpaperDraft"] == wallpaper_image.as_uri()
            assert call("activateControl", "detach-page") == "true"
            assert state()["wallpaperDraft"] == wallpaper_image.as_uri()
            call("draft", "wallpaper", wallpaper_image.as_uri())
            time.sleep(.3)
            assert call("activateControl", "wallpaper-apply") == "true"
            assert state()["wallpaperApplied"] and "wallpaper" in state()["detached"]
            assert state()["detached"] == ["wallpaper"] and not state()["open"]
            call("page", "wallpaper")
            assert not state()["open"] and state()["detached"] == ["wallpaper"]
            call("page", "appearance")
            call("appearanceState", "fixed")
            settle()
            assert call("coordinate", "latitude", "12.345") == "true"
            if args.keyboard:
                subprocess.run(["wtype", "-M", "ctrl", "-M", "shift", "-k", "d", "-m", "shift", "-m", "ctrl"], check=True, timeout=5)
                time.sleep(.2)
                assert "appearance" in state()["detached"] and not state()["open"], state()
            else:
                assert call("activateControl", "detach-page") == "true"
            assert state()["latitudeDraft"] == "12.345"
            call("scenario", "crowded")
            call("page", "overview")
            settle()
            assert call("activateControl", "open-media") == "true"
            assert settle()["page"] == "detail:media"
            assert state()["seekEnabled"]
            if args.keyboard:
                assert call("focusControl", "media", "media-position") == "true"
                subprocess.run(["wtype", "-k", "Right"], check=True, timeout=5)
                assert state()["mediaPosition"] > 45, state()
            assert call("activateControl", "media-shuffle") == "true" and state()["shuffle"]
            for icon, active in [("repeat", True), ("repeat-one", True), ("repeat", False)]:
                assert call("activateControl", "media-repeat") == "true"
                assert (state()["repeatIcon"], state()["repeating"]) == (icon, active)
            screenshot("media-player")
            for page in ["wifi", "bluetooth", "audio", "media", "notifications"]:
                call("page", page)
                settle()
                if page == "media":
                    assert call("activateControl", "select-player-Radio") == "true"
                if page == "audio":
                    assert call("activateControl", "audio-Mixer") == "true"
                    assert call("activateControl", "stream-mute-17") == "true"
                    assert state()["streamMuted"]
                    if args.keyboard:
                        assert call("focusControl", "audio", "stream-volume-17") == "true"
                        subprocess.run(["wtype", "-k", "Left"], check=True, timeout=5)
                        assert abs(state()["streamVolume"] - 0.6) < 0.001
                    screenshot("playback-mixer")
                if page == "notifications":
                    assert call("activateControl", "notification-history") == "true"
                    assert call("setToolField", "notification-filter", "messenger") == "true"
                    assert call("activateControl", "notification-clear-all") == "false"
                    screenshot("history-filter")
                assert call("activateControl", "detach-page") == "true"
                assert page in state()["detached"] and not state()["open"]
            assert state()["mediaPlayer"] == "Radio" and not state()["seekEnabled"]
            assert call("activateControl", "media-repeat") == "false"
            assert call("activateControl", "media-shuffle") == "false"
            assert state()["streamMuted"]
            assert state()["historyFilter"] == "messenger"
            assert call("activateControl", "notification-record-message") == "true"
            assert state()["savedKeys"] == ["download"]
            call("scenario", "empty")
            assert state()["mediaPlayer"] == ""
            assert call("activateControl", "stream-mute-17") == "false"
            call("scenario", "media")
            assert state()["mediaPlayer"] == "Preview player" and state()["shuffle"]
            assert call("activateControl", "media-shuffle") == "true" and not state()["shuffle"]
            assert state()["detachedWifi"] and state()["detachedControls"]
            # Opening/closing the launcher does not close detached views.
            call("openPanel")
            call("close")
            assert len(state()["detached"]) == 7
            if args.keyboard:
                # IPC alone has never supplied Qt with an input seat/serial.
                subprocess.run(["wtype", "-k", "Shift_L"], check=True, timeout=5)
                time.sleep(.2)
            if args.screenshots:
                for page in state()["detached"]:
                    call("page", page)
                    time.sleep(.2)
                    if args.keyboard:
                        assert any(item["section"] == page and item["active"] for item in state()["detachedFocus"]), state()
                    assert call("captureDetached", page, str(args.screenshots / ("detached-" + page + ".png"))) == "true"
                if os.environ.get("NULLSHELL_PREVIEW_CAPTURE_DESKTOP") == "1":
                    subprocess.run(["grim", str(args.screenshots / "detached-windows.png")], check=True, timeout=5)
                time.sleep(.5)
            for light in ["false", "true"]:
                call("light", light)
                for page in ["appearance", "wallpaper"]:
                    call("resizeDetached", page, "420", "320")
                    call("page", page)
                    time.sleep(.4)
                    if page == "wallpaper":
                        geometry = json.loads(call("detailGeometry", page))
                        assert abs(geometry["imageHeight"] - geometry["imageWidth"] * 9 / 16) < 1, geometry
                        assert geometry["contentHeight"] > geometry["viewportHeight"], geometry
                        assert call("focusControl", page, "wallpaper-apply") == "true"
                        time.sleep(.2)
                        assert json.loads(call("detailGeometry", page))["scroll"] > 0
                    if args.screenshots:
                        assert call("captureDetached", page, str(args.screenshots / ("detached-small-" + page + "-" + light + ".png"))) == "true"
                    call("scrollDetail", page)
                    time.sleep(.2)
                    if args.screenshots:
                        assert call("captureDetached", page, str(args.screenshots / ("detached-scrolled-" + page + "-" + light + ".png"))) == "true"
            if args.keyboard:
                subprocess.run(["wtype", "-k", "Escape"], check=True, timeout=5)
                time.sleep(.2)
                assert "wallpaper" not in state()["detached"] and len(state()["detached"]) == 6, state()
            for page in list(state()["detached"]):
                call("closeDetached", page)
            assert not state()["detachedControls"] and not state()["detachedWifi"]
            call("page", "wallpaper")
            assert state()["open"] and state()["wallpaperDraft"] == ""
            call("page", "session")
            assert call("activateControl", "detach-page") == "false"
            finish(process, log)
            print("Panel preview: scenarios, routes, resizing, selection and cleanup passed")
        except BaseException:
            print(log.read_text())
            raise
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            if args.screenshots:
                (args.screenshots / "preview.log").write_text(log.read_text())


if __name__ == "__main__":
    main()

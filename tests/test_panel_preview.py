"""Portable Wayland preview checks. No Nix imports or host service changes.

Requires Python 3 and Quickshell on PATH and a running Wayland compositor.
Optional --keyboard uses wtype; --screenshots captures only the preview card.
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
    only.add_argument("--overview-only", action="store_true", help="Check overview and search geometry")
    only.add_argument("--palette-only", action="store_true", help="Review desktop pages in both palettes")
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
        for _ in range(60):
            value = state()
            geometry = value["card"]
            if geometry == previous and geometry["height"] > 0:
                time.sleep(0.05)
                latest = state()
                if latest["card"] == geometry:
                    return latest
                geometry = latest["card"]
            previous = geometry
            time.sleep(0.06)
        raise AssertionError("Panel geometry did not settle")

    def screenshot(name):
        if args.screenshots:
            path = args.screenshots / (name + ".png")
            assert call("capture", str(path)) == "true"
            from PIL import Image
            decoded = None
            for _ in range(50):
                try:
                    with Image.open(path) as image:
                        image.load()
                        decoded = image.convert("RGB")
                    break
                except (OSError, ValueError):
                    time.sleep(.05)
            assert decoded is not None, "Preview capture did not finish encoding"
            if name.startswith("appearance-"):
                body = decoded.crop((20, 70, decoded.width - 20, decoded.height - 20))
                colors = body.getcolors(body.width * body.height)
                assert max(count for count, _ in colors) < body.width * body.height * .99, "Appearance content was not rendered"

    def check_overview_geometry():
        for width, light in [("620", "false"), ("440", "true")]:
            call("width", width)
            call("light", light)
            call("page", "overview")
            crowded = width == "440"
            call("scenario", "crowded" if crowded else "empty")
            call("footerState", "false", "30" if crowded else "0", str(crowded).lower())
            call("action", "power:power-saver" if crowded else "power:balanced")
            call("action", "notifications-pause" if crowded else "notifications-resume")
            call("scrollOverview", "false")
            card = settle()["card"]
            search = json.loads(call("controlBounds", "launcher-search"))
            left = search["x"] - card["left"]
            right = card["right"] - search["x"] - search["width"]
            top = search["y"] - card["top"]
            assert left > 0 and abs(left - right) <= 1 and abs(top - left) <= 1, (card, search)
            screenshot("overview-" + width + "-" + light)
            status = json.loads(call("controlBounds", "search-status"))
            scope = json.loads(call("controlBounds", "search-scope-@"))
            assert abs(status["y"] + status["height"] / 2 - search["y"] - search["height"] / 2) <= 1, (search, status)
            assert status["x"] > search["x"] and status["x"] + status["width"] <= scope["x"], (search, status, scope)
            call("scrollOverview", "true")
            card = settle()["card"]
            notifications = json.loads(call("controlBounds", "overview-notifications"))
            footer = json.loads(call("controlBounds", "workspace-footer"))
            power = json.loads(call("controlBounds", "power-menu-button"))
            assert power["y"] < notifications["y"], (power, notifications)
            for name in ("footer-power-status", "footer-dnd-status", "footer-mic-status", "footer-awake-status"):
                bounds = json.loads(call("controlBounds", name))
                assert bool(bounds) == crowded, (name, bounds)
            if crowded:
                if args.keyboard:
                    assert call("focusControl", "overview", "settings-idle") == "true"
                    subprocess.run(["wtype", "-k", "Tab"], check=True, timeout=5)
                    assert settle()["focusedItem"] == "power-menu-button"
                above = footer["y"] - notifications["y"] - notifications["height"]
                below = card["bottom"] - footer["y"] - footer["height"]
                assert abs(above - below) <= 1 and 0 < above < top, (notifications, footer, card)
                footer_geom = json.loads(call("footerGeometry"))
                assert abs(footer_geom["leftMargin"] - footer_geom["rightMargin"]) <= 2, footer_geom
            else:
                # Pure dynamic footer collapses completely when workspaces, tray and active state are all empty.
                assert footer == {}, footer
                below = card["bottom"] - notifications["y"] - notifications["height"]
                assert abs(below - top) <= 1, (notifications, card, top)
            screenshot("overview-footer-" + width + "-" + light)
            call("search", ">?")
            settle()
            assert json.loads(call("controlBounds", "launcher-search")) == search
            assert json.loads(call("controlBounds", "search-status")) == {}
        call("action", "power:balanced")
        call("action", "notifications-resume")
        call("footerState", "true", "0", "false")
        call("scenario", "normal")
        call("width", "620")
        call("light", "false")
        call("page", "overview")

    def check_appearance():
        call("page", "overview")
        settle()
        assert call("activateControl", "settings-appearance") == "true"
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
        for width, light, scenario in [
            ("620", "false", "timezone"), ("620", "true", "fixed"),
            ("440", "false", "locating"), ("440", "true", "unavailable"), ("620", "false", "override")
        ]:
            call("width", width)
            call("light", light)
            call("appearanceState", scenario)
            current = settle()
            geometry = json.loads(call("detailGeometry", "appearance"))
            assert current["card"]["height"] < 700, current
            assert geometry["contentHeight"] <= geometry["viewportHeight"] + 1, geometry
            screenshot("appearance-" + width + "-" + light + "-" + scenario)
        assert call("activateControl", "appearance-resume") == "true", state()
        assert state()["overrideUntil"] == 0
        call("activateControl", "appearance-reset")
        assert not state()["preferencesOverridden"]

    def review_palette():
        for light in ["true", "false"]:
            call("light", light)
            palette = "light" if light == "true" else "dark"
            call("width", "620")
            for page in ["overview", "desktop", "wifi", "bluetooth", "audio", "media", "notifications",
                         "appearance", "displays", "idle", "wallpaper", "session", "search"]:
                call("scenario", "media" if page == "media" else "normal")
                if page == "search":
                    call("search", ">")
                else:
                    call("page", page)
                if page == "wallpaper":
                    assert call("draft", "wallpaper", wallpaper_image.as_uri()) == "true"
                current = settle()
                expected = page if page in ["overview", "desktop", "search"] else "detail:" + page
                assert current["page"] == expected and current["dark"] == (light == "false"), current
                if page == "wallpaper":
                    apply = json.loads(call("controlBounds", "wallpaper-apply"))
                    assert apply["y"] + apply["height"] <= current["card"]["bottom"] - 8, (apply, current)
                screenshot(palette + "-620-" + page)

    def finish(process, log):
        call("quit")
        process.wait(timeout=5)
        assert process.returncode == 0
        errors = re.findall(r"^.*(?:TypeError|ReferenceError|SyntaxError|Cannot assign|not a function|failed to load|Binding loop|Cannot anchor).*$", log.read_text(), re.MULTILINE | re.IGNORECASE)
        assert not errors, "\n".join(errors)

    def check_displays():
        def check_card_alignment(side_by_side):
            arrangement = json.loads(call("controlBounds", "display-arrangement-card"))
            fields = json.loads(call("controlBounds", "display-parameters-card"))
            if side_by_side:
                assert arrangement["x"] + arrangement["width"] < fields["x"], (arrangement, fields)
                assert abs(arrangement["y"] - fields["y"]) <= 1, (arrangement, fields)
                assert abs(arrangement["height"] - fields["height"]) <= 1, (arrangement, fields)
            else:
                assert abs(arrangement["x"] - fields["x"]) <= 1, (arrangement, fields)
                assert arrangement["y"] + arrangement["height"] < fields["y"], (arrangement, fields)

        call("page", "displays")
        assert settle()["page"] == "detail:displays"
        assert call("activateControl", "displays-test") == "false", "A clean layout needs no trial"
        assert json.loads(call("displayIssues")) == [], "The fixture layout must start flush"
        for width, light in [("620", "false"), ("440", "true")]:
            call("width", width)
            call("light", light)
            s = settle()
            button = json.loads(call("controlBounds", "displays-test"))
            assert button["height"] >= 32 and button["y"] + button["height"] <= s["card"]["bottom"] - 8, (s, button)
            geometry = json.loads(call("detailGeometry", "displays"))
            assert geometry["contentHeight"] <= geometry["viewportHeight"] + 1, geometry
            check_card_alignment(width == "620")
            screenshot("displays-editor-" + width + ("-light" if light == "true" else "-dark"))
        call("width", "620")
        call("light", "false")

        assert call("displayDrag", "DP-1", "1904", "-6") == "true", state()
        assert [(o["x"], o["y"]) for o in state()["displayDraft"] if o["name"] == "DP-1"] == [(1920, 0)], state()
        assert json.loads(call("displayIssues")) == [], state()

        assert call("displayDragPreview", "DP-1", "1912", "6") == "true", state()
        assert state()["displayDragging"] is True, state()
        screenshot("displays-snap-guide")
        call("displayCancelDrag")

        assert call("displayDrag", "DP-1", "2400", "40") == "true", state()
        issues = json.loads(call("displayIssues"))
        assert [issue["kind"] for issue in issues] == ["detached"], issues
        assert "DP-1" in issues[0]["names"], issues
        assert call("activateControl", "displays-test") == "false", "A detached display must not be tested"
        screenshot("displays-detached")

        assert call("displayDrag", "DP-1", "1500", "0") == "true", state()
        assert [issue["kind"] for issue in json.loads(call("displayIssues"))] == ["overlap"], state()
        assert call("activateControl", "displays-tidy") == "true", state()
        assert json.loads(call("displayIssues")) == [], state()
        assert [(o["x"], o["y"]) for o in state()["displayDraft"] if o["name"] == "DP-1"] == [(1920, 0)], state()

        assert call("displaySelect", "0") == "true"
        assert call("activateControl", "displays-enabled") == "true"
        assert call("displaySelect", "1") == "true"
        assert call("activateControl", "displays-enabled") == "true"
        assert call("activateControl", "displays-test") == "false", "Cannot disable all displays"
        assert call("activateControl", "displays-enabled") == "true"
        assert call("displaySelect", "0") == "true"
        assert call("activateControl", "displays-enabled") == "true"
        assert call("displayValue", "mode", "1280x720@60Hz") == "true"
        assert call("displayValue", "x", "896") == "true"
        if args.keyboard:
            assert call("focusControl", "displays", "displays-scale") == "true"
            subprocess.run(["wtype", "-M", "ctrl", "-k", "a", "-m", "ctrl", "1.25"], check=True, timeout=5)
        else:
            assert call("displayValue", "scale", "1.25") == "true"
        assert json.loads(call("displayIssues")) == [], state()
        screenshot("displays-unsaved")
        assert call("activateControl", "displays-test") == "true"
        s = settle()
        assert s["displayPhase"] == "preview"
        assert (s["displaySubmitted"][0]["width"], s["displaySubmitted"][0]["scale"], s["displaySubmitted"][0]["x"]) == (1280, 1.25, 896), s
        assert s["displayTrialChanges"][0]["name"] == "eDP-1"
        changes = {row["label"]: row["value"] for row in s["displayTrialChanges"][0]["rows"]}
        assert changes == {"Resolution": "1920 × 1080 → 1280 × 720", "Scale": "1× → 1.25×", "Position": "896, 0"}, changes
        assert state()["focusedItem"] == "displays-revert", state()
        widths = set()
        for control in ("displays-confirm", "displays-revert"):
            button = json.loads(call("controlBounds", control))
            assert button["width"] >= 90 and button["y"] + button["height"] <= s["card"]["bottom"] - 8, button
            widths.add(round(button["width"]))
        assert len(widths) == 1, f"Trial actions should be equal width: {widths}"
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
        assert call("activateControl", "displays-test") == "false"
        assert call("activateControl", "displays-tidy") == "true"
        assert json.loads(call("displayIssues")) == [], state()
        assert call("activateControl", "displays-test") == "true"
        settle()
        assert call("activateControl", "displays-revert") == "true"
        assert settle()["lastAction"] == "display-revert"
        screenshot("displays-reverted")

        assert call("displayTopology", "3") == "true"
        names = ("HDMI-A-1", "eDP-1", "DP-1")
        for width in ["620", "440"]:
            call("width", width)
            settle()
            left, center, right = [json.loads(call("controlBounds", "arrangement-output-" + name)) for name in names]
            assert left["x"] < center["x"] < right["x"] and left["y"] < center["y"], (left, center, right)
            assert left["height"] > left["width"] and all(rect["width"] >= 8 for rect in (left, center, right))
            screenshot("displays-three-" + width)
        assert call("displaySelect", "2") == "true"
        assert call("displayValue", "scale", "1.25") == "true"
        assert [issue["kind"] for issue in json.loads(call("displayIssues"))] == ["detached"], state()
        assert call("activateControl", "displays-test") == "false", "A detached display must not be tested"
        assert call("activateControl", "displays-tidy") == "true"
        assert json.loads(call("displayIssues")) == [], state()
        assert call("activateControl", "displays-test") == "true"
        preview = settle()
        assert {d["name"]: d["scale"] for d in preview["displayDraft"]} == {"eDP-1": 1, "DP-1": 1, "HDMI-A-1": 1.25}, preview
        assert preview["displayTrialChanges"] == [{"name": "HDMI-A-1", "rows": [{"label": "Scale", "value": "1× → 1.25×"},
            {"label": "Position", "value": "-864, -456"}]}], preview
        assert call("activateControl", "displays-revert") == "true"
        assert settle()["displayPhase"] == "idle"
        assert call("activateControl", "displays-test") == "false"

        assert call("displayValue", "y", "-200") == "true"
        assert json.loads(call("displayIssues")) == [], state()
        assert call("activateControl", "detach-page") == "true"
        assert "displays" in settle()["detached"]
        initial = json.loads(call("detailGeometry", "displays"))
        assert initial["pageWidth"] >= 850 and initial["arrangementHeight"] > 220, initial
        check_card_alignment(True)
        call("resizeDetached", "displays", "1100", "710")
        time.sleep(.15)
        large = json.loads(call("detailGeometry", "displays"))
        assert large["arrangementWidth"] > initial["arrangementWidth"], (initial, large)
        assert large["arrangementHeight"] > initial["arrangementHeight"], (initial, large)
        call("resizeDetached", "displays", "880", "940")
        time.sleep(.15)
        tall = json.loads(call("detailGeometry", "displays"))
        assert tall["arrangementWidth"] > large["arrangementWidth"], (large, tall)
        assert tall["arrangementHeight"] > initial["arrangementHeight"], (initial, tall)
        check_card_alignment(False)
        call("resizeDetached", "displays", "490", "340")
        time.sleep(.15)
        narrow = json.loads(call("detailGeometry", "displays"))
        assert narrow["arrangementHeight"] < initial["arrangementHeight"], (initial, narrow)
        assert narrow["contentHeight"] > narrow["viewportHeight"], narrow
        assert call("activateControl", "displays-test") == "true"
        assert settle()["displayDraft"][2]["y"] == -200
        assert call("activateControl", "displays-revert") == "true"
        call("closeDetached", "displays")
        assert "displays" not in settle()["detached"]
        assert call("displayTopology", "2") == "true"

    def check_idle():
        call("page", "overview")
        call("footerState", "true", "0", "false")
        settle()
        assert call("activateControl", "footer-awake-status") == "true"
        s = settle()
        assert s["page"] == "detail:idle" and s["idleFields"] == {"dim":"2:30", "lock":"5:00"}
        for width, light in [("620", "false"), ("440", "true")]:
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
        assert call("setToolField", "awake-duration", "37") == "true"
        assert call("activateControl", "awake-duration-apply") == "true"
        settle()
        assert call("activateControl", "awake-duration-apply") == "true"
        call("footerState", "true", "0", "false")

    with tempfile.TemporaryDirectory(prefix="nullshell-preview-test-") as temporary:
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
                time.sleep(0.06)
            else:
                raise AssertionError("Preview IPC did not become ready")
            if args.overview_only:
                check_overview_geometry()
                finish(process, log)
                print("Overview preview: balanced search insets and inline status passed")
                return
            if args.palette_only:
                review_palette()
                finish(process, log)
                print("Panel palettes: 13 routes rendered in both palettes")
                return
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
            check_overview_geometry()

            # Verify redesigned overview structure: 2-up tiles, 2-up sliders, 5-up quick-panels strip.
            names = ("quick-wifi-toggle", "quick-wifi-details", "quick-bluetooth-toggle", "quick-bluetooth-details",
                "volume-details", "settings-appearance", "settings-wallpaper",
                "settings-displays", "settings-idle", "power-menu-button", "overview-notifications")
            bounds = {name: json.loads(call("controlBounds", name)) for name in names}
            for name, rect in bounds.items():
                assert rect.get("width", 0) > 0 and rect.get("height", 0) > 0, (name, rect)
            assert abs(bounds["quick-wifi-details"]["y"] - bounds["quick-bluetooth-details"]["y"]) <= 1, bounds
            assert bounds["quick-wifi-details"]["x"] < bounds["quick-bluetooth-details"]["x"], bounds
            panel_strip = ("settings-appearance", "settings-wallpaper", "settings-displays", "settings-idle", "power-menu-button")
            settings_xs = [bounds[name]["x"] for name in panel_strip]
            settings_ys = [bounds[name]["y"] for name in panel_strip]
            assert settings_xs == sorted(settings_xs) and max(settings_ys) - min(settings_ys) <= 1, bounds

            # Centered dynamic footer balances margins across widths when populated.
            for width in ["440", "620"]:
                call("width", width)
                settle()
                footer = json.loads(call("footerGeometry"))
                assert footer["visible"] and abs(footer["leftMargin"] - footer["rightMargin"]) <= 2, footer
            call("width", "620")

            for light, blur in [("false", "true"), ("true", "false")]:
                call("light", light)
                call("blur", blur)
                material = settle()
                assert material["blur"] == (blur == "true"), material
                assert (material["materialOpacity"] < 1) == material["blur"], material
                screenshot(("light" if light == "true" else "dark") + ("-glass" if blur == "true" else "-solid"))
            call("light", "false")

            for scenario in ["empty", "crowded", "media", "normal"]:
                assert call("scenario", scenario) == "true"
                for page in ["overview", "desktop", "audio", "media", "notifications"]:
                    call("page", page)
                    current = settle()
                    expected = page if page in ["overview", "desktop"] else "detail:" + page
                    assert current["page"] == expected and current["open"] and current["card"]["width"] > 0, current

            call("width", "620")
            call("page", "wifi")
            settle()
            assert call("activateControl", "wifi-device-Enterprise network") == "true"
            settle()
            assert call("activateControl", "wifi-connect") == "false"
            screenshot("wifi-unsupported-620-false")
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
            assert changed["results"] == before["results"] and changed["selectedKey"] == before["selectedKey"]

            call("width", "620")
            call("page", "desktop")
            settle()
            assert call("activateControl", "desktop-shortcuts") == "true"
            settle()
            assert call("shortcutCount") == "2"
            screenshot("shortcuts-620")
            assert call("setToolField", "shortcut-filter", "terminal") == "true"
            assert call("shortcutCount") == "1"

            for mode in ["all", "panel", "operation"]:
                call("search", {"all": ">", "panel": ">?", "operation": ">!"}[mode])
                filtered = settle()
                assert filtered["commandFilter"] == mode
                assert filtered["results"] == (6 if mode == "all" else 3)
                assert filtered["selectedIndex"] == 0
                if mode != "all":
                    assert set(filtered["resultTypes"]) == {mode}
                screenshot("commands-620-false-" + mode)

            call("search", ">")
            if args.keyboard:
                subprocess.run(["wtype", "?"], check=True, timeout=5)
                assert settle()["commandFilter"] == "panel"
                subprocess.run(["wtype", "-k", "BackSpace"], check=True, timeout=5)
                assert settle()["commandFilter"] == "all"
            call("search", "> power")
            assert settle()["results"] == 2
            call("activateControl", "command-filter-operation")
            assert settle()["results"] == 1 and state()["query"] == ">! power"
            call("activateControl", "command-filter-panel")
            assert settle()["results"] == 1 and state()["query"] == ">? power"
            call("activateControl", "command-filter-all")
            assert settle()["results"] == 2 and state()["query"] == "> power"
            call("search", ">!power")
            assert settle()["results"] == 1
            call("activateSelected")
            assert state()["lastAction"] == "activate power:balanced" and state()["commandFilter"] == "all"
            call("search", "> keyboard")
            settle()
            previous = state()["lastAction"]
            call("activateSelected")
            assert state()["lastAction"] == previous and state()["query"] == "> keyboard"
            call("activateControl", "command-filter-panel")
            assert settle()["results"] == 0
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
                assert call("focusControl", "overview", "settings-idle") == "true"
                subprocess.run(["wtype", "-k", "Tab"], check=True, timeout=5)
                focused = settle()
                assert focused["focusedItem"] == "power-menu-button", focused
                assert focused["focusY"] >= -1 and focused["focusY"] + focused["focusHeight"] <= focused["overviewHeight"] + 1, focused
                screenshot("overview-keyboard-focus")

            call("page", "notifications")
            call("activateControl", "notification-quiet")
            assert settle()["doNotDisturb"]
            screenshot("notifications-quiet-440-true")
            call("activateControl", "notification-quiet")
            assert not settle()["doNotDisturb"]

            for section in ["wifi", "bluetooth"]:
                call("page", "overview")
                assert call("activateControl", "quick-" + section + "-toggle") == "true"
                assert state()["page"] == "overview" and state()["lastAction"] == section + "-toggle"
                assert call("activateControl", "quick-" + section + "-details") == "true"
                assert state()["page"] == "detail:" + section

            call("page", "overview")
            call("width", "440")
            for section in ["appearance", "wallpaper", "displays", "idle"]:
                assert call("activateControl", "settings-" + section) == "true"
                assert settle()["page"] == "detail:" + section
                if args.keyboard:
                    subprocess.run(["wtype", "-k", "Escape"], check=True, timeout=5)
                else:
                    call("page", "overview")
                assert settle()["page"] == "overview"
            if args.keyboard:
                assert call("focusControl", "overview", "settings-displays") == "true"
                assert settle()["focusedItem"] == "settings-displays"
                subprocess.run(["wtype", "-k", "Return"], check=True, timeout=5)
                assert settle()["page"] == "detail:displays"
                call("page", "overview")

            call("width", "620")
            call("light", "false")
            for condition in ["busy", "unavailable"]:
                call("quickState", condition)
                for section in ["wifi", "bluetooth"]:
                    assert call("activateControl", "quick-" + section + "-toggle") == "false"
                    assert call("activateControl", "quick-" + section + "-details") == "true"
                    call("page", "overview")
                settle()
            call("quickState", "error")
            settle()
            call("quickState", "normal")

            check_appearance()
            check_displays()
            check_idle()

            call("page", "overview")
            settle()
            assert call("activateControl", "power-menu-button") == "true"
            assert settle()["page"] == "detail:session"
            assert call("activateControl", "power-profile-power-saver") == "true"
            assert state()["lastAction"] == "power:power-saver"
            assert call("activateControl", "power-profile-balanced") == "true"
            assert state()["lastAction"] == "power:balanced"
            for action in ["logout", "reboot", "poweroff"]:
                previous = state()["lastAction"]
                assert call("activateControl", "power-action-" + action) == "true"
                assert state()["lastAction"] == previous
                settle()
                assert call("activateControl", "power-cancel") == "true"
                assert state()["lastAction"] == previous
                call("activateControl", "power-action-" + action)
                assert call("activateControl", "power-confirm") == "true"
                assert state()["lastAction"] == "session:" + action
            call("sessionState", "unavailable")
            settle()
            assert call("activateControl", "power-action-poweroff") == "false"
            call("sessionState", "normal")
            call("activateControl", "power-action-suspend")
            assert state()["lastAction"] == "session:suspend"

            call("page", "wallpaper")
            assert call("draft", "wallpaper", wallpaper_image.as_uri()) == "true"
            settle()
            geometry = json.loads(call("detailGeometry", "wallpaper"))
            assert abs(geometry["imageHeight"] - geometry["imageWidth"] * 9 / 16) < 1, geometry
            assert state()["card"]["height"] <= 700, state()
            assert call("activateControl", "wallpaper-choose") == "true"
            time.sleep(.2)
            assert state()["dialogOpen"] and state()["open"]
            call("cancelFileDialog")
            assert not state()["dialogOpen"] and state()["wallpaperDraft"] == wallpaper_image.as_uri()
            assert call("activateControl", "detach-page") == "true"
            assert state()["wallpaperDraft"] == wallpaper_image.as_uri()
            call("draft", "wallpaper", wallpaper_image.as_uri())
            time.sleep(.15)
            assert call("activateControl", "wallpaper-apply") == "true"
            assert state()["wallpaperApplied"] and state()["detached"] == ["wallpaper"] and not state()["open"]

            call("page", "appearance")
            call("appearanceState", "fixed")
            settle()
            assert call("coordinate", "latitude", "12.345") == "true"
            if args.keyboard:
                subprocess.run(["wtype", "-M", "ctrl", "-M", "shift", "-k", "d", "-m", "shift", "-m", "ctrl"], check=True, timeout=5)
                time.sleep(.15)
                assert "appearance" in state()["detached"] and not state()["open"], state()
            else:
                assert call("activateControl", "detach-page") == "true"
            assert state()["latitudeDraft"] == "12.345"

            call("scenario", "crowded")
            call("page", "overview")
            settle()
            assert call("activateControl", "open-media") == "true"
            assert settle()["page"] == "detail:media" and state()["seekEnabled"]
            if args.keyboard:
                assert call("focusControl", "media", "media-position") == "true"
                subprocess.run(["wtype", "-k", "Right"], check=True, timeout=5)
                assert state()["mediaPosition"] > 45, state()
            assert call("activateControl", "media-shuffle") == "true" and state()["shuffle"]
            for icon, active in [("repeat", True), ("repeat-one", True), ("repeat", False)]:
                assert call("activateControl", "media-repeat") == "true"
                assert (state()["repeatIcon"], state()["repeating"]) == (icon, active)

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
                if page == "notifications":
                    assert call("activateControl", "notification-history") == "true"
                    assert call("setToolField", "notification-filter", "messenger") == "true"
                    assert call("activateControl", "notification-clear-all") == "false"
                assert call("activateControl", "detach-page") == "true"
                assert page in state()["detached"] and not state()["open"]

            assert state()["mediaPlayer"] == "Radio" and not state()["seekEnabled"]
            assert call("activateControl", "notification-record-message") == "true"
            assert state()["savedKeys"] == ["download"]
            call("scenario", "media")
            assert state()["mediaPlayer"] == "Preview player" and state()["shuffle"]
            assert call("activateControl", "media-shuffle") == "true" and not state()["shuffle"]
            assert len(state()["detached"]) == 7

            if args.keyboard:
                subprocess.run(["wtype", "-k", "Shift_L"], check=True, timeout=5)
                time.sleep(.1)
                call("resizeDetached", "wallpaper", "420", "320")
                call("page", "wallpaper")
                time.sleep(.2)
                assert call("focusControl", "wallpaper", "wallpaper-apply") == "true"
                for _ in range(20):
                    scrolled = json.loads(call("detailGeometry", "wallpaper"))
                    if scrolled["scroll"] > 0:
                        break
                    time.sleep(.06)
                assert scrolled["scroll"] > 0, (scrolled, state()["detachedFocus"])
                subprocess.run(["wtype", "-k", "Escape"], check=True, timeout=5)
                time.sleep(.15)
                assert "wallpaper" not in state()["detached"], state()

            for page in list(state()["detached"]):
                call("closeDetached", page)
            assert not state()["detachedControls"] and not state()["detachedWifi"]
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

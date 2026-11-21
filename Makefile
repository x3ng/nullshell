PREFIX ?= /usr/local
DESTDIR ?=
CARGO_BUILD_JOBS ?= 2
CARGO_TARGET_DIR ?= backend/target

.DEFAULT_GOAL := help

.PHONY: check-command check-session check-sleep check-settings help build helper install check check-backend check-pairing check-preview check-material check-appearance install-greeter install-assets

help:
	@printf '%s\n' \
	  'Usage: make <target> (default: help; no build or installation)' \
	  '' \
	  '  build / helper    Build the Rust helper in release mode' \
	  '  install           Build and install runtime commands (PREFIX, DESTDIR)' \
	  '  install-greeter   Install checkout QML using sudo; no service restart' \
	  '  check             Run lightweight syntax and launcher checks' \
	  '  check-command     Check search, app dispatch and notifications on a private bus' \
	  '  check-backend     Run Rust tests' \
	  '  check-sleep       Check logind coordination on a private bus' \
	  '  check-session     Check session commands using fake executables' \
	  '  check-pairing     Check the pairing adapter' \
	  '  check-material    Check surface capabilities (Wayland session required)' \
	  '  check-preview     Check panel previews (Wayland session required)' \
	  '  check-appearance  Build helper and check appearance/wallpaper export' \
	  '  check-settings    Check Settings portal on a private bus'

build: helper

helper:
	CARGO_BUILD_JOBS=$(CARGO_BUILD_JOBS) CARGO_TARGET_DIR="$(abspath $(CARGO_TARGET_DIR))" cargo build --locked --release --manifest-path backend/Cargo.toml

# No services are enabled and no user configuration is written by installation.
install: helper
	install -Dm755 bin/nullshell "$(DESTDIR)$(PREFIX)/bin/nullshell"
	install -Dm755 "$(CARGO_TARGET_DIR)/release/nullshell-helper" "$(DESTDIR)$(PREFIX)/bin/nullshell-helper"
	install -Dm755 bin/nullshell-install-greeter "$(DESTDIR)$(PREFIX)/bin/nullshell-install-greeter"
	install -Dm755 bin/nullshell-lock "$(DESTDIR)$(PREFIX)/bin/nullshell-lock"
	install -Dm755 bin/nullshell-migrate-state "$(DESTDIR)$(PREFIX)/bin/nullshell-migrate-state"
	install -Dm644 integration/nullshell.portal "$(DESTDIR)$(PREFIX)/share/xdg-desktop-portal/portals/nullshell.portal"
	install -d "$(DESTDIR)$(PREFIX)/share/dbus-1/services"
	sed 's|@HELPER@|$(PREFIX)/bin/nullshell-helper|g' integration/org.freedesktop.impl.portal.desktop.nullshell.service.in > "$(DESTDIR)$(PREFIX)/share/dbus-1/services/org.freedesktop.impl.portal.desktop.nullshell.service"

# Optional system-owned greeter/test resources; never deploy a user config.
install-assets:
	install -d "$(DESTDIR)$(PREFIX)/share/nullshell"
	install -m644 greeter-interface.version "$(DESTDIR)$(PREFIX)/share/nullshell/greeter-interface.version"
	cp -R *.qml *.js components adapters greeter lock polkit preview wallpaper.json "$(DESTDIR)$(PREFIX)/share/nullshell/"
	if [ -d assets ]; then cp -R assets "$(DESTDIR)$(PREFIX)/share/nullshell/"; fi

check:
	sh -n bin/nullshell
	sh -n bin/nullshell-install-greeter
	sh -n bin/nullshell-lock
	sh -n bin/nullshell-migrate-state
	./bin/nullshell --help
	python3 tests/test_migration.py
	python3 tests/test_launcher.py

check-pairing:
	python3 tests/test_pairing_adapter.py

check-command:
	python3 tests/test_command_panel.py

check-backend:
	CARGO_BUILD_JOBS=$(CARGO_BUILD_JOBS) cargo test --locked --manifest-path backend/Cargo.toml

# Run inside a Wayland session. Uses only Python and Quickshell from PATH.
check-material:
	python3 tests/test_surface_capabilities.py

check-preview:
	python3 tests/test_panel_preview.py

check-appearance: helper
	python3 tests/test_wallpaper.py "$(CARGO_TARGET_DIR)/release/nullshell-helper"
	python3 tests/test_solar_appearance.py "$(CARGO_TARGET_DIR)/release/nullshell-helper"
	python3 tests/test_appearance.py "$(CARGO_TARGET_DIR)/release/nullshell-helper"

# Use the installed, system-configured installer. sudo only wraps this file operation.
install-greeter:
	sudo nullshell-install-greeter --source "$(CURDIR)"

# Uses a fresh bus; never connects to host services.
check-settings: helper
	python3 tests/test_settings_portal.py "$(CARGO_TARGET_DIR)/release/nullshell-helper"

check-sleep: helper
	python3 tests/test_sleep_bridge.py "$(CARGO_TARGET_DIR)/release/nullshell-helper"

check-session:
	python3 tests/test_session_actions.py

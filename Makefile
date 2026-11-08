PREFIX ?= /usr/local
DESTDIR ?=
CARGO_BUILD_JOBS ?= 2
CARGO_TARGET_DIR ?= backend/target

.PHONY: build helper install check check-backend check-preview check-material

build: helper

helper:
	CARGO_BUILD_JOBS=$(CARGO_BUILD_JOBS) CARGO_TARGET_DIR="$(abspath $(CARGO_TARGET_DIR))" cargo build --locked --release --manifest-path backend/Cargo.toml

# No services are enabled and no user configuration is written by installation.
install: helper
	install -Dm755 bin/nullshell "$(DESTDIR)$(PREFIX)/bin/nullshell"
	install -Dm755 "$(CARGO_TARGET_DIR)/release/nullshell-helper" "$(DESTDIR)$(PREFIX)/bin/nullshell-helper"
	install -Dm755 bin/nullshell-lock "$(DESTDIR)$(PREFIX)/bin/nullshell-lock"
	install -Dm755 bin/nullshell-migrate-state "$(DESTDIR)$(PREFIX)/bin/nullshell-migrate-state"
	install -d "$(DESTDIR)$(PREFIX)/share/nullshell"
	install -m644 integration/hypridle.conf "$(DESTDIR)$(PREFIX)/share/nullshell/hypridle.conf"
	cp -R *.qml *.js components adapters greeter lock polkit preview wallpaper.json "$(DESTDIR)$(PREFIX)/share/nullshell/"

check:
	sh -n bin/nullshell
	sh -n bin/nullshell-lock
	sh -n bin/nullshell-migrate-state
	./bin/nullshell --help
	python3 tests/test_migration.py
	python3 tests/test_launcher.py

check-backend:
	CARGO_BUILD_JOBS=$(CARGO_BUILD_JOBS) cargo test --locked --manifest-path backend/Cargo.toml

# Run inside a Wayland session. Uses only Python and Quickshell from PATH.
check-material:
	python3 tests/test_surface_capabilities.py

check-preview:
	python3 tests/test_panel_preview.py

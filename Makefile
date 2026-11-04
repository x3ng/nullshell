PREFIX ?= /usr/local
DESTDIR ?=
USER_UNIT_DIR ?= $(PREFIX)/lib/systemd/user

.PHONY: install check

# No services are enabled and no user configuration is written by installation.
install:
	install -Dm755 bin/nullshell "$(DESTDIR)$(PREFIX)/bin/nullshell"
	install -Dm755 bin/nullshell-lock "$(DESTDIR)$(PREFIX)/bin/nullshell-lock"
	install -Dm755 bin/nullshell-migrate-state "$(DESTDIR)$(PREFIX)/bin/nullshell-migrate-state"
	install -d "$(DESTDIR)$(PREFIX)/share/nullshell"
	install -m644 integration/hypridle.conf "$(DESTDIR)$(PREFIX)/share/nullshell/hypridle.conf"
	cp -R qml/. "$(DESTDIR)$(PREFIX)/share/nullshell/"
	install -d "$(DESTDIR)$(USER_UNIT_DIR)"
	for unit in integration/systemd/*; do sed 's|@BINDIR@|$(PREFIX)/bin|g' "$$unit" > "$(DESTDIR)$(USER_UNIT_DIR)/$${unit##*/}"; done

check:
	sh -n bin/nullshell
	sh -n bin/nullshell-lock
	sh -n bin/nullshell-migrate-state
	./bin/nullshell --help

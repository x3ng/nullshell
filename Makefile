PREFIX ?= /usr/local
DESTDIR ?=

.PHONY: install check

# No services are enabled and no user configuration is written by installation.
install:
	install -Dm755 bin/nullshell "$(DESTDIR)$(PREFIX)/bin/nullshell"
	install -d "$(DESTDIR)$(PREFIX)/share/nullshell"
	cp -R qml/. "$(DESTDIR)$(PREFIX)/share/nullshell/"

check:
	sh -n bin/nullshell
	./bin/nullshell --help

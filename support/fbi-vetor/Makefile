CARGO ?= cargo
PREFIX ?= /usr/local
DESTDIR ?=
TARGET ?=
TARGET_DIR ?= target
TARGET_OPTION = $(if $(TARGET),--target $(TARGET))
BINARY = $(TARGET_DIR)/$(if $(TARGET),$(TARGET)/)release/fbi

.PHONY: all build test install

all: build

build:
	$(CARGO) build --locked --release --target-dir "$(TARGET_DIR)" $(TARGET_OPTION)

test:
	$(CARGO) test --locked --target-dir "$(TARGET_DIR)" $(TARGET_OPTION)

install: build
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -m 0755 "$(BINARY)" "$(DESTDIR)$(PREFIX)/bin/fbi"

# Use a locale available even on minimal Raspberry Pi installations.
export LC_ALL := C

SIGNAGED_ROOT := $(shell cat install-root)

BUILD_ROOT ?= $(HOME)/.cache/signaged/build
RUBY_BUILD_DIR = $(BUILD_ROOT)/ruby-$(RUBY_VERSION)
FBI_BUILD_DIR := $(BUILD_ROOT)/fbi-vetor

RUST_VERSION := 1.85.0
RUSTUP ?= $(HOME)/.cargo/bin/rustup

RUBY_VERSION = 4.0.9
RUBY_SHA256 = c35350682ff050b79702d57ade4516e7336063f510155d19fb2fb5b3f3909511

# PI_SERVICES := signaged.service signaged_player.service auth_unit.service git_update.service
PI_SERVICES := signaged.service signaged_player.service git_update.service

install-on-pi:

	@. /etc/os-release && test "$$VERSION_CODENAME:$$(dpkg --print-architecture)" = buster:armhf || { echo "Use Raspberry Pi OS Buster 32-bit (armhf)."; exit 1; }
	sudo apt-get update
	# Install Ruby and the runtime gems
	sudo apt-get install -y build-essential ca-certificates curl wget libssl-dev libyaml-dev zlib1g-dev omxplayer kbd
	$(MAKE) install-ruby-on-pi
	sudo /usr/local/bin/gem install dotenv -v 2.7.6 --no-document

	$(MAKE) install-fbi-on-pi
	$(MAKE) install-services-on-pi

install-ruby-on-pi:
	mkdir -p "$(BUILD_ROOT)"
	wget -O "$(RUBY_BUILD_DIR).tar.gz" https://cache.ruby-lang.org/pub/ruby/4.0/ruby-$(RUBY_VERSION).tar.gz
	printf '%s  %s\n' "$(RUBY_SHA256)" "$(RUBY_BUILD_DIR).tar.gz" | sha256sum --check
	tar -xzf "$(RUBY_BUILD_DIR).tar.gz" -C "$(BUILD_ROOT)"
	cd "$(RUBY_BUILD_DIR)" && ./configure --prefix=/usr/local --disable-install-doc
	$(MAKE) -C "$(RUBY_BUILD_DIR)"
	sudo make -C "$(RUBY_BUILD_DIR)" install

install-fbi-on-pi:
	@if [ ! -x "$(RUSTUP)" ]; then \
		set -e; installer=$$(mktemp); trap 'rm -f "$$installer"' EXIT; \
		curl -fsSL https://sh.rustup.rs -o "$$installer"; \
		sh "$$installer" -y --profile minimal --default-toolchain none --no-modify-path; \
	fi
	"$(RUSTUP)" toolchain install "$(RUST_VERSION)" --profile minimal
	$(MAKE) -C support/fbi-vetor CARGO='"$(RUSTUP)" run $(RUST_VERSION) cargo' TARGET_DIR="$(abspath $(FBI_BUILD_DIR))" test build
	sudo install -D -m 0755 "$(FBI_BUILD_DIR)/release/fbi" /usr/local/bin/fbi

install-services-on-pi:
	@set -e; for unit in $(PI_SERVICES); do \
		sed 's|@SIGNAGED_ROOT@|$(SIGNAGED_ROOT)|g' "services/$$unit" | \
			sudo tee "/etc/systemd/system/$$unit" >/dev/null; \
	done
	sudo systemctl daemon-reload
	sudo systemctl mask getty@tty2.service
	sudo systemctl enable $(PI_SERVICES)

install: install-on-pi

.PHONY: install install-ruby-on-pi install-fbi-on-pi install-on-pi install-services-on-pi

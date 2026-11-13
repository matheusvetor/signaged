# Use a locale available even on minimal Raspberry Pi installations.
export LC_ALL := C

RUBY_VERSION = 4.0.9
RUBY_SHA256 = c35350682ff050b79702d57ade4516e7336063f510155d19fb2fb5b3f3909511

# PI_SERVICES := signaged.service signaged_player.service auth_unit.service git_update.service
PI_SERVICES := signaged.service signaged_player.service git_update.service

install-on-pi:

	# Install Ruby and the runtime gems
	sudo apt-get install -y build-essential ca-certificates wget libssl-dev libyaml-dev zlib1g-dev
	wget -O ruby-$(RUBY_VERSION).tar.gz https://cache.ruby-lang.org/pub/ruby/4.0/ruby-$(RUBY_VERSION).tar.gz
	printf '%s  %s\n' "$(RUBY_SHA256)" "ruby-$(RUBY_VERSION).tar.gz" | sha256sum --check
	tar -xzf ruby-$(RUBY_VERSION).tar.gz
	cd ruby-$(RUBY_VERSION) && ./configure --prefix=/usr/local
	$(MAKE) -C ruby-$(RUBY_VERSION)
	sudo make -C ruby-$(RUBY_VERSION) install
	sudo /usr/local/bin/gem install dotenv -v 2.7.6 --no-document

	$(MAKE) -C support/fbi-vetor build
	sudo install -d /usr/local/bin
	sudo install -m 0755 support/fbi-vetor/target/release/fbi /usr/local/bin/fbi

	$(MAKE) install-services-on-pi

install-services-on-pi:
	sudo install -m 0644 $(addprefix services/,$(PI_SERVICES)) /etc/systemd/system/
	sudo systemctl daemon-reload
	sudo systemctl enable $(PI_SERVICES)

install: install-on-pi

.PHONY: install install-on-pi install-services-on-pi

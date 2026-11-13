
install-on-pi:

	# Install Ruby
	wget https://cache.ruby-lang.org/pub/ruby/2.6/ruby-2.6.3.tar.gz
	tar -xzvf ruby-2.6.3.tar.gz
	cd ruby-2.6.3 && ./configure && $(MAKE) && sudo $(MAKE) install

	$(MAKE) -C support/fbi-vetor build
	sudo install -d /usr/local/bin
	sudo install -m 0755 support/fbi-vetor/target/release/fbi /usr/local/bin/fbi

	# Copy signaged to init.d
	sudo rm -r -f /etc/init.d/signaged
	sudo ln -s /home/pi/signaged/signaged /etc/init.d

	# Add signaged to boot start
	update-rc.d signaged start 30

install: install-on-pi

.PHONY: install install-on-pi

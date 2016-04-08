
install-on-macosx:
	brew install nodejs npm phantomjs
	sudo npm update
	sudo npm install temp phantom

install-on-pi:
        # Install Ruby
        wget https://cache.ruby-lang.org/pub/ruby/2.3/ruby-2.3.0.tar.gz
        tar -xzvf ruby-2.3.0.tar.gz
        cd ruby-2.3.0/
        ./configure
        make
        sudo make install
	sudo ln -s /usr/local/bin/ruby /usr/bin/ruby

        # Copy fbi
	sudo cp support/fbi /usr/bin
	sudo apt-get install ffmpeg
        sudo apt-get install --reinstall ttf-mscorefonts-installer

	# Extract nodejs for RaspberryPi
	tar -zxf support/node-v0.10.28-linux-arm-pi.tar.gz

	# Remove any old node version. Create the dir again
	sudo rm -r -f /opt/node
	sudo mkdir /opt/node

	# Copy the expanded files
	sudo cp -r node-v*arm-pi*/* /opt/node

	# Symlink node and npm to somewhere already in the path. Debate where...
	sudo ln -s -f /opt/node/bin/node /usr/bin/node
	sudo ln -s -f /opt/node/bin/npm /usr/bin/npm

	# Move phantomjs
	sudo cp support/phantomjs /usr/bin

	# Fix node executable name
	sudo ln -s /usr/bin/nodejs /usr/bin/node

	# Get a newer npm
	sudo npm update

	# Install node modules
	sudo npm install temp phantom@0.9.0

	# Copy signaged to init.d
	sudo rm -r -f /etc/init.d/signaged
	sudo ln -s /home/pi/signaged/signaged /etc/init.d

	# Add signaged to boot start
	update-rc.d signaged start 30

install: install-on-pi
	mkdir -p downloads
	mkdir -p downloads/article
	mkdir -p downloads/video

.PHONY: install install-on-macosx install-on-pi

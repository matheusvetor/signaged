
install-on-macosx:
	brew install nodejs npm phantomjs
	sudo npm update
	sudo npm install temp phantom

install-on-pi:
	# sudo apt-get install ruby nodejs npm
	sudo apt-get install ruby npm

	# Install Node for RaspberryPi
	sudo cp support/node-v0.10.28-linux-arm-pi/bin/node /usr/bin/node
	# Download and extract phantomjs for RaspberryPi
	# wget https://github.com/aeberhardo/phantomjs-linux-armv6l/archive/master.zip
	# unzip master.zip
	# tar xjf phantomjs-linux-armv6l-master/phantomjs-1.9.0-linux-armv6l.tar.bz2
	# Install phantomjs
	sudo cp support/phantomjs-1.9.0-linux-armv6l/bin/phantomjs /usr/local/bin
	# Fix node executable name
	# sudo ln -s /usr/bin/nodejs /usr/bin/node
	# Get a newer npm
	sudo npm update
	# Install node modules
	sudo npm install temp phantom

install: install-on-pi
	mkdir -p downloads
	mkdir -p downloads/article
	mkdir -p downloads/video

.PHONY: install install-on-macosx install-on-pi

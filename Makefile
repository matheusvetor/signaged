
install-on-macosx:
    brew install nodejs npm phantomjs
    sudo npm update
    sudo npm install temp phantom

install-on-pi:

    # Install Ruby
    wget https://cache.ruby-lang.org/pub/ruby/2.3/ruby-2.3.1.tar.gz
    tar -xzvf ruby-2.3.1.tar.gz
    cd ruby-2.3.1/
    ./configure
    make
    sudo make install

    sudo apt-get build-dep fbi
    sudo apt-get install imagemagick
    sudo apt-get install --reinstall ttf-mscorefonts-installer

    # Install NodeJS from official repository
    curl -sL https://deb.nodesource.com/setup_5.x | sudo -E bash -
    sudo apt-get install -y nodejs

    # Copy fbi
    sudo cp support/fbi /usr/bin

    # Copy phantomjs
    sudo cp support/phantomjs /usr/bin

    # Get a newer npm
    sudo npm update

    # Install node modules
    sudo npm install temp phantom

    # Copy signaged to init.d
    sudo rm -r -f /etc/init.d/signaged
    sudo ln -s /home/pi/signaged/signaged /etc/init.d

    # Add signaged to boot start
    update-rc.d signaged enable

install: install-on-pi
    mkdir -p downloads
    mkdir -p downloads/article
    mkdir -p downloads/video

.PHONY: install install-on-macosx install-on-pi

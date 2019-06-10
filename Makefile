
install-on-pi:

    # Install Ruby
    wget https://cache.ruby-lang.org/pub/ruby/2.6/ruby-2.6.3.tar.gz
    tar -xzvf ruby-2.6.3.tar.gz
    cd ruby-2.6.3/
    ./configure
    make
    sudo make install

    sudo apt-get build-dep fbi
    sudo apt-get install libjpeg8-dev

    # Copy fbi
    sudo cp support/fbi /usr/bin

    # Copy signaged to init.d
    sudo rm -r -f /etc/init.d/signaged
    sudo ln -s /home/pi/signaged/signaged /etc/init.d

    # Add signaged to boot start
    update-rc.d signaged start 30

install: install-on-pi

.PHONY: install install-on-macosx install-on-pi

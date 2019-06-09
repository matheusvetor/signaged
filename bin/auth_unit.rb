#!/usr/bin/env ruby

require 'dotenv'
require 'logger'

Dotenv.load
logger = Logger.new('/home/pi/signaged/logs/auth_unit.log', 5, 100000)

while true
  if ENV['NEED_TO_CONNECT_UNIT_WIFI']
    `/usr/local/bin/casperjs /home/pi/signaged/autologin/app.js`
    logger.info("Trying to connect into unit network")
  else
    logger.info("No need to connect into unit network")
  end
  sleep 600
end

#!/usr/bin/env ruby

require 'dotenv'
require 'logger'

Dotenv.load('/home/pi/signaged/.env')
logger = Logger.new('/home/pi/signaged/logs/git_update.log', 5, 100000)

while true
  command = "/usr/bin/git -C /home/pi/signaged pull origin #{ENV['GIT_BRANCH']}"
  system(command)
  logger.info("Trying to get code updates: #{command}")

  sleep 300
end

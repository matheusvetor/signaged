#!/usr/bin/env ruby

require 'shellwords'
require 'dotenv'
require 'logger'
require_relative '../lib/synchronizer.rb'

Dotenv.load
logger = Logger.new('/home/pi/signaged/logs/signaged.log', 5, 100000000)

# The production server address
SERVER = if ENV['SERVER_NAME'].nil?
           'http://staging.tvopen.com.br'
         else
           ENV['SERVER_NAME']
         end

# This machine's identification
SERIAL = `cat /proc/cpuinfo | grep Serial | cut -d' ' -f2`.gsub!(/[^0-9A-Za-z]/, '')

# Get the expanded base directory
base_dir = File.expand_path(File.dirname(__FILE__))

content_dir = "#{base_dir}/../downloads"
logger.info("Started Signaged - Using content dir #{content_dir}")

while true
  synchronizer = Synchronizer.new(SERVER, SERIAL)
  current_schedule = synchronizer.get_local_json
  synchronizer.sync
  logger.info('Syncronized')

  sleep [current_schedule['check_after'], 150].max
end

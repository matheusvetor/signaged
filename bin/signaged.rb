#!/usr/bin/env ruby

require 'shellwords'
require 'dotenv'
require 'logger'
require_relative '../lib/synchronizer.rb'

module SignagedSync
  def self.run
    project = File.expand_path('..', __dir__)
    Dotenv.load(File.join(project, '.env'))
    logger = Logger.new(File.join(project, 'logs', 'signaged.log'), 5, 100000)

    server = ENV.fetch('SERVER_NAME', 'http://staging.tvopen.com.br')

    # This machine's identification
    serial = ENV.fetch('SIGNAGED_SERIAL') do
      `cat /proc/cpuinfo | grep Serial | cut -d' ' -f2`.gsub(/[^0-9A-Za-z]/, '')
    end

    # Get the expanded base directory
    base_dir = File.expand_path(File.dirname(__FILE__))

    $content_dir = "#{base_dir}/../downloads"
    logger.info("Started Signaged - Using content dir #{$content_dir}")

    while true
      synchronizer = Synchronizer.new(server, serial)

      current_schedule = synchronizer.sync
      logger.info('Syncronized')

      sleep [current_schedule['check_after'], 150].max
    end
  end
end

SignagedSync.run if $PROGRAM_NAME == __FILE__

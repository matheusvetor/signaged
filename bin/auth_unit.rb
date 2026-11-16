#!/usr/bin/env ruby

require 'shellwords'
require 'dotenv'
require 'logger'

module AuthUnit
  def self.run
    project = File.expand_path('..', __dir__)
    Dotenv.load(File.join(project, '.env'))
    logger = Logger.new(File.join(project, 'logs', 'auth_unit.log'), 5, 100000)

    while true
      if ENV['CONNECT_UNIT_WIFI'].eql?('true')
        `/usr/local/bin/casperjs #{Shellwords.escape(project)}/lib/auth_unit.js`
        logger.info("Trying to connect into unit network")
      else
        logger.info("No need to connect into unit network")
      end

      sleep 21600
    end
  end
end

AuthUnit.run if $PROGRAM_NAME == __FILE__

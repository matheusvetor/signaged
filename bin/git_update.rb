#!/usr/bin/env ruby

require 'dotenv'
require 'logger'

module GitUpdate
  def self.run
    Dotenv.load('/home/tvopen/signaged/.env')
    logger = Logger.new('/home/tvopen/signaged/logs/git_update.log', 5, 100000)

    while true
      command = "/usr/bin/git -C /home/tvopen/signaged pull origin #{ENV['GIT_BRANCH']}"
      system(command)
      logger.info("Trying to get code updates: #{command}")

      sleep 300
    end
  end
end

GitUpdate.run if $PROGRAM_NAME == __FILE__

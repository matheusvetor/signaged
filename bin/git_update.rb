#!/usr/bin/env ruby

require 'shellwords'
require 'dotenv'
require 'logger'

module GitUpdate
  def self.run
    project = File.expand_path('..', __dir__)
    Dotenv.load(File.join(project, '.env'))
    logger = Logger.new(File.join(project, 'logs', 'git_update.log'), 5, 100000)

    while true
      command = "/usr/bin/git -C #{Shellwords.escape(project)} pull origin #{ENV['GIT_BRANCH']}"
      system(command)
      logger.info("Trying to get code updates: #{command}")

      sleep 300
    end
  end
end

GitUpdate.run if $PROGRAM_NAME == __FILE__

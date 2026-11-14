#!/usr/bin/env ruby

require 'dotenv'
require 'logger'
require_relative '../lib/synchronizer.rb'

module SignagedPlayer
  def self.run
    project = File.expand_path('..', __dir__)
    Dotenv.load(File.join(project, '.env'))
    logger = Logger.new(File.join(project, 'logs', 'signaged_player.log'), 5, 100000)

    server = ENV.fetch('SERVER_NAME', 'http://staging.tvopen.com.br')

    # This machine's identification
    serial = ENV.fetch('SIGNAGED_SERIAL') do
      `cat /proc/cpuinfo | grep Serial | cut -d' ' -f2`.gsub(/[^0-9A-Za-z]/, '')
    end

    logger.info('Started signaged player.')

    $content_dir = File.join(project, 'downloads')
    mpv = %w[/usr/bin/mpv --no-config --vo=drm --sws-scaler=fast-bilinear
             --no-terminal --no-input-default-bindings]

    synchronizer = Synchronizer.new(server, serial)

    while true
      logger.info('Signaged - Starting loop.')
      current_schedule = synchronizer.get_local_json

      unless current_schedule && !current_schedule['items'].empty?
        system(*mpv, '--no-audio', '--image-display-duration=1', '--',
               File.join(project, 'assets', 'images', 'black.ppm'))
        sleep 1
        next
      end

      items = Schedule.parse_items(JSON.generate(current_schedule['items']))
      Schedule.cleanup_unused_files(items)

      available = items.select { |item| File.file?(item.file_path) }
      available.each do |item|

        options = if item.type == 'video'
                    %w[--hwdec=auto --framedrop=decoder+vo].tap do |flags|
                      flags << '--no-audio' unless item.audio_enabled
                    end
                  else
                    ['--no-audio', "--image-display-duration=#{item.display_time}"]
                  end

        logger.info("Signaged Player: playing #{item.file_path}")
        system(*mpv, *options, '--', item.file_path)
      end

      sleep 1 if available.empty?
    end
  end
end

SignagedPlayer.run if $PROGRAM_NAME == __FILE__

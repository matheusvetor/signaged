#!/usr/bin/env ruby

require 'shellwords'
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

    # Get the expanded base directory
    base_dir = File.expand_path(File.dirname(__FILE__))
    $content_dir = "#{base_dir}/../downloads"

    synchronizer = Synchronizer.new(server, serial)

    while true
      logger.info('Signaged - Starting loop.')
      current_schedule = synchronizer.get_local_json

      unless current_schedule && !current_schedule['items'].empty?
        sleep 1
        next
      end

      serialized_items = JSON.generate(current_schedule['items'])

      items = Schedule.parse_items(serialized_items)
      Schedule.cleanup_unused_files(items)

      video_player_pid = -1
      image_player_pid = -1

      %x(fbi -T 2 -reset)

      items.each do |item|
        case item.type
        when 'video'
          file_path = item.file_path
          if File.exist?(file_path)
            command = "omxplayer -o hdmi --no-keys -n -1 #{Shellwords.escape(file_path)} > /dev/null"
            command = "omxplayer -o hdmi --no-keys #{Shellwords.escape(file_path)} > /dev/null" if item.audio_enabled
            logger.info("Signaged Player: spawn: #{command}")
            video_player_pid = spawn(command)
            # item.send_impression
            status = Process.waitpid2(video_player_pid)

            logger.info("Signaged Player: omxplayer finished: #{status[1]}")
          end
        when 'article', 'widget', 'image'
          logger.info('Signaged - Starting image.' + item.filename)
          file_path = item.file_path
          if File.exist?(file_path)
            command = "fbi -T 2 -a -noverbose #{Shellwords.escape(file_path)} > /dev/null"
            image_player_pid = spawn('fbi', '-T', '2', '-a', '-noverbose', file_path, out: File::NULL)
            logger.info("Signaged Player: spawn: #{command}")
            # item.send_impression
            sleep item.display_time
            begin
              Process.kill('TERM', image_player_pid)
            rescue Errno::ESRCH
              # The renderer already exited.
            end
            Process.waitpid(image_player_pid)

            logger.info('Signaged Player: image finished')
          end
        end
      end
    end
  end
end

SignagedPlayer.run if $PROGRAM_NAME == __FILE__

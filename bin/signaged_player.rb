#!/usr/bin/env ruby

require 'shellwords'
require 'dotenv'
require 'logger'
require_relative '../lib/synchronizer.rb'

Dotenv.load('/home/pi/signaged/.env')
logger = Logger.new('/home/pi/signaged/logs/signaged_player.log', 5, 100000)

# The production server address
SERVER = if ENV['SERVER_NAME'].nil?
           'http://staging.tvopen.com.br'
         else
           ENV['SERVER_NAME']
         end

# This machine's identification
SERIAL = `cat /proc/cpuinfo | grep Serial | cut -d' ' -f2`.gsub!(/[^0-9A-Za-z]/, '')

logger.info('Started signaged player.')

# Get the expanded base directory
base_dir = File.expand_path(File.dirname(__FILE__))
$content_dir = "#{base_dir}/../downloads"

synchronizer = Synchronizer.new(SERVER, SERIAL)

while true
  logger.info('Signaged - Starting loop.')
  current_schedule = synchronizer.get_local_json

  serialized_items = JSON.generate(current_schedule['items'])

  items = Schedule.parse_items(serialized_items)

  video_player_pid = -1
  image_player_pid = -1

  %x(fbi -T 2 -reset)

  items.each do |item|
    case item.type
    when 'video'
      file_path = Shellwords.escape(item.file_path)
      if File.exist?(file_path)
        command = "omxplayer -o hdmi --no-keys -n -1 #{file_path} > /dev/null 2>&1"
        command = "omxplayer -o hdmi --no-keys #{file_path} > /dev/null 2>&1" if item.audio_enabled
        logger.info("Signaged Player: spawn: #{command}")
        video_player_pid = spawn(command)
        # item.send_impression
        status = Process.waitpid2(video_player_pid)

        logger.info("Signaged Player: omxplayer finished: #{status[1]}")
      end
    when 'article', 'widget', 'image'
      logger.info('Signaged - Starting image.')
      file_path = Shellwords.escape(item.file_path)
      if File.exist?(file_path)
        command = "fbi -T 2 -a -noverbose #{file_path} > /dev/null 2>&1"
        image_player_pid = spawn(command)
        logger.info("Signaged Player: spawn: #{command}")
        # item.send_impression
        sleep item.display_time
        system('killall fbi')

        logger.info('Signaged Player: image finished')
      end
    end
  end
end

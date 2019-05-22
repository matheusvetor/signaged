#!/usr/bin/env ruby

require 'shellwords'
require 'dotenv'
require 'logger'
require_relative '../lib/synchronizer.rb'

Dotenv.load
logger = Logger.new('/home/pi/signaged/logs/signaged_player.log', 5, 100000000)

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
current_schedule = synchronizer.get_local_json

serialized_items = JSON.generate(current_schedule['items'])

items = Schedule.parse_items(serialized_items)
# Schedule.cleanup_unused_files(items)

ScheduleRun = Struct.new(:type, :items)
command_seq = []

items.each do |it|
  if command_seq.empty?
    run = ScheduleRun.new
    run.type = it.type
    run.items = [it]
    command_seq << run
  else
    if command_seq.last.type == it.type
      command_seq.last.items << it
    else
      run = ScheduleRun.new
      run.type = it.type
      run.items = [it]
      command_seq << run
    end
  end
end

logger.info('Schedule summary:')
command_seq.each do |it|
  logger.info("#{it.items.length} item(s) of type #{it.type}")
end

video_player_pid = -1
image_player_pid = -1

if command_seq.empty?
  %x(fbi -T 2 -a -noverbose #{base_dir}/../assets/images/no-content.png > /dev/null 2>&1)
end

%x(fbi -T 2 -reset)

while true
  command_seq.each do |it|
    case it.type
    when 'video'
      it.items.each do |video|
        file_path = Shellwords.escape(video.file_path)
        if File.exist?(file_path)
          command = "omxplayer -o hdmi --no-keys -n -1 #{file_path} > /dev/null 2>&1"
          command = "omxplayer -o hdmi --no-keys #{file_path} > /dev/null 2>&1" if video.allowed_audio
          logger.info("Signaged Player: spawn: #{command}")
          video_player_pid = spawn(command)
          video.send_impression
          status = Process.waitpid2(video_player_pid)

          logger.info("Signaged Player: omxplayer finished: #{status[1]}")
        end
      end
    when 'article', 'widget', 'image'
      it.items.each do |image|
        file_path = Shellwords.escape(image.file_path)
        if File.exist?(file_path)
          command = "fbi -T 2 -a -noverbose #{file_path} > /dev/null 2>&1"
          image_player_pid = spawn(command)
          logger.info("Signaged Player: spawn: #{command}")
          image.send_impression
          sleep image.display_time
          system("killall fbi")

          logger.info("Signaged Player: fbi probably killed")
        end
      end
    end
  end
end

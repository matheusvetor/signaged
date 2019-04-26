#!/usr/bin/env ruby

require 'shellwords'
require_relative '../lib/synchronizer.rb'

serialized_items = ARGV[0]
if !serialized_items
  puts $PROGRAM_NAME + ": Usage: signaged_player.rb [ITEMS_JSON]"
  exit(1)
end

puts $PROGRAM_NAME + ": Started signaged player."

# Get the expanded base directory
base_dir = File.expand_path(File.dirname(__FILE__))

$content_dir = "#{base_dir}/../downloads"

File.open("#{$content_dir}/signaged_player.pid", "wb") do |file|
  file.write(Process.pid)
end

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

puts $PROGRAM_NAME + ": schedule summary:"
command_seq.each do |it|
  puts $PROGRAM_NAME + ": " + it.items.length.to_s + " item(s) of type " + it.type
end

video_player_pid = -1
image_player_pid = -1
should_end = false

Signal.trap("TERM") do
  puts "Terminating Player"
  should_end = true
end

if command_seq.empty?
  %x(fbi -T 2 -a -noverbose #{base_dir}/../assets/images/no-content.png > /dev/null 2>&1)
end

while !should_end
  %x(fbi -T 2 -reset > /dev/null 2>&1)

  command_seq.each do |it|
    case it.type
    when "video"
      it.items.each do |video|
        file_path = Shellwords.escape(video.file_path)
        if File.exist?(file_path)
          command = "omxplayer -o hdmi --no-keys -n -1 #{file_path} > /dev/null 2>&1"
          command = "omxplayer -o hdmi --no-keys #{file_path} > /dev/null 2>&1" if video.allowed_audio
          puts "#{$PROGRAM_NAME}: spawn: #{command}"
          video_player_pid = spawn(command)
          video.send_impression
          status = Process.waitpid2(video_player_pid)
          puts "#{$PROGRAM_NAME}: omxplayer finished: #{status[1]}"
        end
      end
    when "image"
      it.items.each do |image|
        file_path = Shellwords.escape(image.file_path)
        if File.exist?(file_path)
          command = "fbi -T 2 -a -noverbose #{file_path} > /dev/null 2>&1"
          image_player_pid = spawn(command)
          puts "#{$PROGRAM_NAME}: spawn: #{command}"
          image.send_impression
          sleep image.display_time
          system("killall fbi")
          puts "#{$PROGRAM_NAME}: fbi probably killed"
        end
      end
    when "article", "widget"
      it.items.each do |article|
        file_path = Shellwords.escape(article.file_path)
        if File.exist?(file_path)
          command = "fbi -T 2 -a -noverbose #{file_path} > /dev/null 2>&1"
          image_player_pid = spawn(command)
          puts "#{$PROGRAM_NAME}: spawn: #{command}"
          article.send_impression
          sleep article.display_time
          system("killall fbi")
          puts "#{$PROGRAM_NAME}: fbi probably killed"
        end
      end
    end
  end
end

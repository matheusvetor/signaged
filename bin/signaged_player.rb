#!/usr/bin/env ruby

require 'shellwords'
require_relative '../lib/synchronizer.rb'

serialized_itineraries = ARGV[0]
if !serialized_itineraries
  puts $PROGRAM_NAME + ": Usage: signaged_player.rb [ITINERARIES_JSON]"
  exit(1)
end

puts $PROGRAM_NAME + ": Started signaged player."

# Get the expanded base directory
base_dir = File.expand_path(File.dirname(__FILE__))

$content_dir = "#{base_dir}/../downloads"

File.open("#{$content_dir}/signaged_player.pid", "wb") do |file|
  file.write(Process.pid)
end

itineraries = Schedule.parse_itineraries(serialized_itineraries)

ScheduleRun = Struct.new(:type, :items)
command_seq = []

itineraries.each do |it|
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

if comand_seq.blank?
  exec "fbi -T 2 -reset"
else
  exec "fbi -T 2 -a -noverbose #{base_dir}/../assets/images/no-content.png > /dev/null 2>&1"
end

while !should_end
  command_seq.each do |it|
    case it.type
    when "video"
      it.items.each do |p|
        file_path = Shellwords.escape(p.file_path)
        command = "omxplayer -o hdmi #{file_path} > /dev/null 2>&1"
        puts "#{$PROGRAM_NAME}: spawn: #{command}"
        video_player_pid = spawn(command)
        status = Process.waitpid2(video_player_pid)
        puts "#{$PROGRAM_NAME}: omxplayer finished: #{status[1]}"
      end
    when "article"
      it.items.each do |article|
        file_path = Shellwords.escape(article.rendered_image_path)
        command = "fbi -T 2 -a -noverbose #{file_path} > /dev/null 2>&1"
        image_player_pid = spawn(command)
        puts "#{$PROGRAM_NAME}: spawn: #{command}"
        sleep article.article_duration
        killall_pid = system("killall fbi")
        puts "#{$PROGRAM_NAME}: fbi probably killed"
      end
    end
  end
end

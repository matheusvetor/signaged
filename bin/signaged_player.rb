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
command_seq.each do |it|
  puts $PROGRAM_NAME + ": show " + it.to_s
  case it.type
  when "video"
    if video_player_pid >= 0
      kill video_player_pid
    end
    params = it.items.map{|i| Shellwords.escape(i.file_path) }.join(" ")
    command = "omxplayer -o hdmi " + params
    video_player_pid = spawn(command)
  when "article"
    if image_player_pid >= 0
      kill image_player_pid
    end
    params = it.items.map{|i| Shellwords.escape(i.rendered_image_path) }.join(" ")
    command = "fbi -a -blend 600 -noverbose " + params
    image_player_pid = spawn(command)
  end
end

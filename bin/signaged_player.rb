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
should_end = false

term_signal_handler = proc {
  should_end = true
}

Signal.trap("INT", term_signal_handler)
Signal.trap("TERM", term_signal_handler)

#system("/usr/bin/tvservice -p")

while !should_end
  command_seq.each do |it|
    case it.type
    when "video"
      #params = it.items.map{|i| Shellwords.escape(i.file_path) }
      #params.each do |p|
      it.items.each do |p|
        file_path = Shellwords.escape(p.file_path)
        command = "omxplayer -o hdmi #{file_path} > /dev/null"
        puts "#{$PROGRAM_NAME}: spawn: #{command}"
        video_player_pid = spawn(command)
        status = Process.waitpid2(video_player_pid)
        puts "#{$PROGRAM_NAME}: omxplayer finished: #{status[1]}"
      end
    when "article"
      timeout = 5
      # params = it.items.map{|i| Shellwords.escape(i.video_path) }
      params = it.items.map{|i| Shellwords.escape(i.rendered_image_path) }
      params.each do |p|
        command = "fbi -T 2 -a -noverbose #{p} > /dev/null"
        # command = "omxplayer -o hdmi #{p} > /dev/null"
        #puts "#{$PROGRAM_NAME}: spawn: #{command}"
        image_player_pid = spawn(command)
        puts "#{$PROGRAM_NAME}: spawn: #{command}"
        sleep timeout
	killall_pid = system("killall fbi")
        puts "#{$PROGRAM_NAME}: fbi probably killed"
      end
    end
  end
end

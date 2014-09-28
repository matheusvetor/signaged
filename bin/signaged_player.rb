#!/usr/bin/env ruby

require_relative '../lib/synchronizer.rb'

serialized_itineraries = ARGV[0]
if !serialized_itineraries
  puts $PROGRAM_NAME + ": Usage: signaged_player.rb [ITINERARIES_JSON]"
  exit(1)
end

puts $PROGRAM_NAME + ": Started signaged player."

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

command_seq.each do |it|
  puts $PROGRAM_NAME + ": show " + it.to_s
end

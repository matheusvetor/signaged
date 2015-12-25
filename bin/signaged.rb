#!/usr/bin/env ruby

require "shellwords"
require_relative '../lib/synchronizer.rb'

usage = $PROGRAM_NAME + ": Usage: signage.rb SERVER_URL [SERIAL]"

default_serial = "CD9AK29HYCGPAH09"
prod_server = "http://admin.tvopen.com.br"

# The production server address
SERVER = begin
           if ARGV[0]
             ARGV[0]
           else
             puts $PROGRAM_NAME + ": error: Invalid server URL"
             puts usage
             exit 1
           end
         end

# This machine's identification
SERIAL = begin
           if ARGV[1]
             ARGV[1]
           else
             exec "cat /proc/cpuinfo | grep Serial | cut -d' ' -f2"
           end
         end

# Get the expanded base directory
base_dir = File.expand_path(File.dirname(__FILE__))

$content_dir = "#{base_dir}/../downloads"
puts $PROGRAM_NAME + ": Using content dir " + $content_dir

# A loop that downloads and show the files
last_schedule_id = -1
player_pid = -1

while true
  synchronizer = Synchronizer.new(SERVER, SERIAL)
  current_schedule = synchronizer.get_local_json
  unless current_schedule
    current_schedule = synchronizer.sync
  end

  if current_schedule['id'] != last_schedule_id
    player_pid = begin
	           File.read([$content_dir, 'signaged_player.pid'].join('/')).to_i
                 rescue
                   -1
                 end
    
    puts "PID on File: '#{player_pid}'"

    if player_pid > 0
      # ask the player to stop if it's running
      begin
        Process.kill("TERM", player_pid)
        Process.wait
      rescue
        puts "PID #{player_pid} not found."
      end
    end

    # spawn the player
    serialized_itineraries = Shellwords.escape JSON.generate(current_schedule['itineraries'])
    spawn("#{base_dir}/signaged_player.rb #{serialized_itineraries}")
  end

  last_schedule_id = current_schedule['id']

  current_schedule = synchronizer.sync

  sleep [current_schedule['check_after'] || 7200 , 43200].min
end

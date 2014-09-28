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

# Spawn the html2img server
workind_dir = base_dir + '/../downloads'
html2img_pid = spawn('node ' + base_dir + '/html2img-server.js ' + workind_dir)
puts $PROGRAM_NAME + ": Spawning node html2img-server.js... " + html2img_pid.to_s
sleep 4 # Wait for the server to fully start

# A loop that downloads and show the files
last_schedule_id = -1
player_pid = -1
while true
  synchronizer = Synchronizer.new(SERVER, SERIAL)
  current_schedule = synchronizer.sync

  if current_schedule['id'] != last_schedule_id
    if player_pid >= 0
      # stop the player if it's running
      Process.kill(player_pid)
    end

    # spawn the player
    serialized_itineraries = Shellwords.escape JSON.generate(current_schedule['itineraries'])
    player_pid = spawn("#{base_dir}/signaged_player.rb #{serialized_itineraries}")
  end

  last_schedule_id = current_schedule['id']

  sleep 10
end

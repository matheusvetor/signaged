require_relative '../lib/synchronizer.rb'

usage = "Usage: signage.rb SERVER_URL [SERIAL]"

default_serial = "CD9AK29HYCGPAH09"
prod_server = "http://admin.tvopen.com.br"

# The production server address
SERVER = begin
           if ARGV[0]
             ARGV[0]
           else
             puts "error: Invalid server URL"
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

synchronizer = Synchronizer.new(SERVER, SERIAL)
synchronizer.sync

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

# Get the expanded base directory
base_dir = File.expand_path(File.dirname(__FILE__))

# Spawn the html2img server
workind_dir = base_dir + '/../downloads'
html2img_pid = spawn('node ' + base_dir + '/html2img-server.js ' + workind_dir)
print "Spawning node html2img-server.js... "
sleep 4 # Wait for the server to fully start
puts html2img_pid

# Download files
synchronizer = Synchronizer.new(SERVER, SERIAL)
synchronizer.sync

while true
  sleep 2
end

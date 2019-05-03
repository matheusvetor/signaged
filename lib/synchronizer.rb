#! /usr/bin/ruby

require 'rubygems'
require 'net/http'
require 'json'
require 'tempfile'

class Loadable
  attr_reader :impress_url, :can_download

  def initialize(url, impress_url)
    @url = URI.parse(url)
    @impress_url = URI.parse(impress_url)
    @can_download = true
  end

  def send_impression
    spawn("curl #{@impress_url}")
  end

  def filename
    File.basename(@url.path)
  end

  def relative_file_path
    "/#{@type}/#{filename}"
  end

  def file_path
    "#{$content_dir}#{relative_file_path}"
  end

  def response
    puts "#{$PROGRAM_NAME}: Downloading file #{url.to_s} into #{file_path}"
    begin
      Net::HTTP.get_response(@url)
    rescue
      @can_download = false
    end
  end

  def download
    if @can_download && !File.exist?(file_path)
      begin
        tmp_file_path = "/home/pi/signaged/tmp/download.#{rand(1000000)}"
        tmp_file = File.open(tmp_file_path, 'wb')
        tmp_file.write(response.body)
        tmp_file.close
        FileUtils.move(tmp_file_path, file_path)
      rescue
        puts "Can't download #{file_path}"
      end
    end
  end
end

class Video < Loadable
  attr_reader :type, :url, :allowed_audio

  def initialize(url, impress_url, allowed_audio)
    super(url, impress_url)
    @type = 'video'
    @allowed_audio = allowed_audio
  end
end

class Image < Loadable
  attr_reader :type, :url, :display_time

  def initialize(url, impress_url, display_time)
    super(url, impress_url)
    @type = 'image'
    @display_time = display_time
  end
end

class Article < Loadable
  attr_reader :type, :url, :display_time

  def initialize(url, impress_url, display_time)
    super(url, impress_url)
    @type = 'article'
    @display_time = display_time
  end
end

class Widget < Article
  attr_reader :type, :url, :display_time

  def initialize(url, impress_url, display_time)
    super(url, impress_url, display_time)
    @type = 'widget'
    @display_time = display_time
  end
end

class Schedule
  def self.parse_items(serialized_items)
    parsed_items = JSON.parse(serialized_items)
    items = []
    parsed_items.each do |item|
      url = item['url']
      impress_url = item['impress_url']
      item = case item['type']
             when 'video'
               allowed_audio = item['allowed_audio']
               Video.new(url, impress_url, allowed_audio)
             when 'article'
               display_time = item['display_time']
               Article.new(url, impress_url, display_time)
             when 'image'
               display_time = item['display_time']
               Image.new(url, impress_url, display_time)
             when 'widget'
               display_time = item['display_time']
               Widget.new(url, impress_url, display_time)
             end
      items << item
    end
    items
  end

  def self.cleanup_unused_files(items)
    video_files =   items.select{ |item| item.class == Video }
    article_files = items.select{ |item| item.class == Article }
    image_files =   items.select{ |item| item.class == Image }
    widget_files =  items.select{ |item| item.class == Widget }
    article_png_files = []
    widget_png_files =  []
    article_files.each { |item| article_png_files << "#{item.filename}.png" }
    widget_files.each  { |item| widget_png_files  << "#{item.filename}.png" }

    delete_article_files =  Dir.entries("/home/pi/signaged/downloads/article").reject { |f| File.directory? f } - [article_png_files, article_files.map(&:filename)].flatten
    delete_widget_files =   Dir.entries("/home/pi/signaged/downloads/widget").reject  { |f| File.directory? f } - [widget_png_files, widget_files.map(&:filename)].flatten
    delete_video_files =    Dir.entries("/home/pi/signaged/downloads/video").reject   { |f| File.directory? f } - video_files.map(&:filename)
    delete_image_files =    Dir.entries("/home/pi/signaged/downloads/image").reject   { |f| File.directory? f } - image_files.map(&:filename)

    FileUtils.rm(delete_article_files + delete_widget_files + delete_video_files + delete_image_files)
  end
end

class Synchronizer
  attr_accessor :items, :can_download

  def initialize(server, serial)
    @server = server
    @serial = serial
    @items = []
    @can_download = true
  end

  def items_uri
    URI "#{@server}/api/devices/#{@serial}/sync.json"
  end

  def response
    begin
      Net::HTTP.get_response items_uri
    rescue
      @can_download = false
    end
  end

  def json_response
    begin
      parsed_json = JSON.parse response.body

      File.open("#{$content_dir}/#{@serial}.json", "wb") do |file|
        file.write(response.body)
      end

      parsed_json
    rescue
      get_local_json(true)
    end
  end

  def get_local_json(do_rescue = false)
    return false unless do_rescue && File.exist?("#{$content_dir}/#{@serial}.json")

    begin
      file = File.open("#{$content_dir}/#{@serial}.json")
      parsed_json = JSON.parse(file.read)
      file.close
      parsed_json
    rescue
      puts "Can't download JSON items. No find the local file"
    end
  end

  def create_wifi_config(json)

    wifi_config0 = <<-EOF
network={
  ssid="#{json['wifi_name']}"
  key_mgmt=NONE
}
    EOF

    wifi_config1 = <<-EOF
network={
  ssid="#{json['wifi_name']}"
  psk="#{json['wifi_password']}"
}
    EOF

    wifi_config = json['wifi_password'].empty? ? wifi_config0  : wifi_config1

    File.open("/etc/wpa_supplicant/wpa_supplicant.conf", "wb") do |file|
      file.write(wifi_config)
    end
  end

  def sync
    json = json_response

    create_wifi_config(json['wifi_config']) unless json['wifi_config'].nil?

    json['items'].each do |item|
      url = item['url']
      impress_url = item['impress_url']
      _item = case item['type']
             when 'video'
               allowed_audio = item['allowed_audio']
               Video.new(url, impress_url, allowed_audio)
             when 'article'
               display_time = item['display_time']
               Article.new(url, impress_url, display_time)
             when 'image'
               display_time = item['display_time']
               Image.new(url, impress_url, display_time)
             when 'widget'
               display_time = item['display_time']
               Widget.new(url, impress_url, display_time)
             end
      _item.download if @can_download
      @items << _item
    end

    return json
  end
end

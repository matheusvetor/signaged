#! /usr/bin/ruby

require 'rubygems'
require 'net/http'
require 'json'
require 'tempfile'

class Loadable
  attr_reader :impress_url
  def initialize(url, impress_url)
    @url = URI.parse(url)
    @impress_url = URI.parse(impress_url)
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
    Net::HTTP.get_response(@url)
  end

  def download
    unless File.exist?(file_path)
      tmp_file_path = 'download.' + rand(1000000).to_s
      tmp_file = File.open(tmp_file_path, "wb")
      tmp_file.write(response.body)
      tmp_file.close
      FileUtils.move(tmp_file_path, file_path)
    end
  end
end

class Video < Loadable
  attr_reader :type, :url, :disable_audio

  def initialize(url, impress_url, disable_audio = nil)
    super(url, impress_url)
    @type = "video"
    @disable_audio = !!disable_audio
  end
end

class Image < Loadable
  attr_reader :type, :url, :display_time

  def initialize(url, impress_url, display_time)
    super(url, impress_url)
    @type = "image"
    @display_time = display_time
  end
end

class Article < Loadable
  attr_reader :type, :url, :display_time

  def initialize(url, impress_url, display_time)
    super(url, impress_url)
    @type = "article"
    @display_time = display_time
  end

  # article always get file
  def download
    tmp_file_path = 'download.' + rand(1000000).to_s
    tmp_file = File.open(tmp_file_path, "wb")
    tmp_file.write(response.body)
    tmp_file.close
    FileUtils.move(tmp_file_path, file_path, force: true)
    download_rendered_page
  end

  def rendered_page_response
    url = "http://localhost:3000/?file_path=#{relative_file_path}"
    puts "#{$PROGRAM_NAME}: Downloading file #{url}"
    Net::HTTP.get_response(URI.parse(url))
  end

  def rendered_image_path
    "#{file_path}.png"
  end

  def download_rendered_page
    unless File.exist?(rendered_image_path)
      tmp_file = Tempfile.new(filename)
      tmp_file.write(rendered_page_response.body)
      FileUtils.move(tmp_file.path, rendered_image_path, force: true)
    end
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
               Video.new(url, impress_url)
             when 'article'
               display_time = item['display_time']
               Article.new(url, impress_url, display_time)
             when 'image'
               display_time = item['display_time']
               Image.new(url, impress_url, display_time)
             end
      items << item
    end
    items
  end
end

class Synchronizer
  attr_accessor :items

  def initialize(server, serial)
    @server = server
    @serial = serial
    @items = []
  end

  def items_uri
    URI "#{@server}/api/devices/#{@serial}/sync.json"
  end

  def response
    Net::HTTP.get_response items_uri
  end

  # {
  #   id: "f212512",
  #   check_after:  43000
  #   disable_audio: true
  #   items: [
  #     {
  #       type: "video" | "article" | ...,
  #       url: "http://..."
  #     },
  #     ...
  #   ]
  # }

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
      parsed_json = JSON.parse file.read
      file.close
      parsed_json
    rescue
      raise "Can't download JSON items no find the local file"
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
  psk="#{json['wifi_pass']}"
}
    EOF

    wifi_config = json['wifi_pass'].empty? ? wifi_config0  : wifi_config1

    File.open("/etc/wpa_supplicant/wpa_supplicant.conf", "wb") do |file|
      file.write(wifi_config)
    end
  end

  def sync
    json = json_response

    create_wifi_config(json['wifi_config']) unless json['wifi_config'].nil?

    disable_audio = json['disable_audio']
    json['items'].each do |item|
      url = item['url']
      impress_url = item['impress_url']
      _item = case item['type']
             when 'video'
               Video.new(url, impress_url)
             when 'article'
               display_time = item['display_time']
               Article.new(url, impress_url, display_time)
             when 'image'
               display_time = item['display_time']
               Image.new(url, impress_url, display_time)
             end
      _item.download
      @items << _item
    end

    return json
  end

  def cleanup_unused_files
    video_files = @items.select{ |item| item.class == Video }
    article_files = @items.select{ |item| item.class == Article }
    article_png_files = []
    article_files.each { |item| article_png_files << "#{item.filename}.png" }

    delete_article_files =  Dir.entries("/home/pi/signaged/downloads/article").reject { |f| File.directory? f } - [article_png_files, article_files.map(&:filename)].flatten

    delete_video_files =  Dir.entries("/home/pi/signaged/downloads/video").reject { |f| File.directory? f } - video_files.map(&:filename)

    FileUtils.cd('/home/pi/signaged/downloads/article') do
      FileUtils.rm(delete_article_files)
    end

    FileUtils.cd('/home/pi/signaged/downloads/video') do
      FileUtils.rm(delete_video_files)
    end
  end
end

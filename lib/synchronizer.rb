#! /usr/bin/ruby

require 'rubygems'
require 'net/http'
require 'json'
require 'tempfile'

# Downloadable object
class Loadable
  def initialize(url)
    @url = URI.parse(url)
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
    Net::HTTP.get_response @url
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

# Videos can be downloaded
class Video < Loadable
  attr_reader :type, :url
  
  def initialize(url)
    @url = URI.parse(url)
    @type = "video"
  end
end

# HTML articles can be downloaded
class Article < Loadable
  attr_reader :type, :url

  def initialize(url)
    @url = URI.parse(url)
    @type = "article"
  end

  def download
    super
    download_rendered_page
  end

  def rendered_page_response
    url = 'http://localhost:3000/?file_path=' + relative_file_path
    puts $PROGRAM_NAME + ": Downloading file " + url
    Net::HTTP.get_response URI.parse(url)
  end

  def download_rendered_page
    rendered_image_path = file_path + '.png'
    unless File.exist?(rendered_image_path)
      tmp_file = Tempfile.new(filename)
      tmp_file.write(rendered_page_response.body)
      FileUtils.move(tmp_file.path, rendered_image_path)
    end
  end
end

class Schedule
  def self.parse_itineraries(serialized_itineraries)
    parsed_itineraries = JSON.parse(serialized_itineraries)
    itineraries = []
    parsed_itineraries.each do |itinerary|
      url = itinerary['url']
      item = itinerary['type'] == 'video' ? Video.new(url) : Article.new(url)
      itineraries << item
    end
    itineraries
  end
end

class Synchronizer
  attr_accessor :itineraries

  def initialize(server, serial)
    @server = server
    @serial = serial
    @itineraries = []
  end

  def itineraries_uri
    URI "#{@server}/api/devices/#{@serial}.json"
  end

  def response
    Net::HTTP.get_response itineraries_uri
  end

  # {
  #   id: "f212512",
  #   itineraries: [
  #     {
  #       type: "video" | "article" | ...,
  #       url: "http://..."
  #     },
  #     ...
  #   ]
  # }
  def json_response
    begin
      JSON.parse response.body
    rescue
      begin
        file = File.open("#{$content_dir}/#{@serial}.json")
        parsed_json = JSON.parse file.read
        file.close
      rescue
        raise "Can't download JSON itinerary no find the local file"
      end
      parsed_json
    end
  end

  def sync
    json = json_response
    json['itineraries'].each do |itinerary|
      url = itinerary['url']
      item = itinerary['type'] == 'video' ? Video.new(url) : Article.new(url)
      item.download
      @itineraries << item
    end
    return json
  end
end

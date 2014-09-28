#! /usr/bin/ruby

require 'rubygems'
require 'net/http'
require 'json'

$content_dir = '/Users/felipe/code/signaged/downloads'

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
    Net::HTTP.get_response @url
  end

  def download
    unless File.exist?(file_path)
      File.open(file_path, "wb") do |file|
        file.write(response.body)
      end
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
    puts url
    @url = URI.parse(url)
    @type = "article"
  end

  def download
    super
    download_rendered_page
  end

  def rendered_page_response
    url = 'http://localhost:3000/?file_path=' + relative_file_path
    puts url
    Net::HTTP.get_response URI.parse(url)
  end

  def download_rendered_page
    rendered_image_path = file_path + '.png'
    puts rendered_image_path
    unless File.exist?(rendered_image_path)
      File.open(rendered_image_path, "wb") do |file|
        file.write(rendered_page_response.body)
      end
    end
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
    JSON.parse response.body
  end

  def sync
    json = json_response
    json['itineraries'].each do |itinerary|
      url = itinerary['url']
      item = itinerary['type'] == 'video' ? Video.new(url) : Article.new(url)
      item.download
      @itineraries << item
    end
  end
end

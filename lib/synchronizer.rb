#! /usr/bin/ruby

require 'rubygems'
require 'net/http'
require 'json'

content_dir = '/Users/felipe/code/signage/downloads'

# Downloadable object
class Loadable
  def initialize(url)
    @url = url
  end

  def filename
    uri = URI.parse(url)
    File.basename(uri.path)
  end

  def file_path
    "#{content_dir}/#{@type}/#{@filename}"
  end

  def response
    Net::HTTP.get_response url
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
  @type = "video"
end

# HTML articles can be downloaded
class Article < Loadable
  @type = "article"
end

class Synchronizer
  attr_accessor :itineraries

  def initialize(server, serial)
    @server = server
    @serial = serial
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
    puts itineraries_uri
    json = json_response
    json['itineraries'].each do |itinerary|
      item = itinerary['type'] == 'video' ? Video.new(itinerary.url) : Article.new(itinerary.url)
      item.download
      @itineraries << item
    end
  end
end

#! /usr/bin/ruby

require 'rubygems'
require 'net/http'
require 'json'
require 'slim'


class Loadable
  def initialize(args)
    args.each do |k, v|
      self.class.class_eval{attr_accessor(k.to_sym)} unless respond_to?(k.to_sym)
      send("#{k}=", v)
    end
  end

  def download_file
    file_exist = File.exist?(file_path)

    unless file_exist
      File.open(file_path, "wb") do |file|
        file.write(response.body)
      end
    end
  end

  def response
    Net::HTTP.get_response remote_file
  end

  def file_path
    "#{@type}/#{@file}"
  end

  def remote_file
    URI "#{SERVER}/uploads/#{@type}/#{@file}"
  end
end

class Video < Loadable
end

class Article < Loadable
end

class HtmlGenerator
  attr_accessor :itineraries

  def initialize
    yield self if block_given?
  end

  def layout
    File.read("layouts/layout.slim")
  end

  def generate_partial(itinerary)
    partial = File.read("layouts/#{itinerary.type}.slim")
    Slim::Template.new { partial }.render(itinerary)
  end

  def generate_itineraries
    itineraries = ""

    @itineraries.each do |itinerary|
      partial = generate_partial(itinerary)
      itineraries << partial
    end

    itineraries
  end

  def generate
    l = Slim::Template.new { layout }

    rendered = l.render { generate_itineraries }

    File.open('index.html', "wb") do |file|
      file.write(rendered)
    end
  end
end

class Synchronizer
  attr_accessor :serial, :server, :itineraries

  def initialize
    yield self if block_given?
    @itineraries = []
  end

  def api
    URI "#{@server}/api/devices/#{@serial}.json"
  end

  def response
    Net::HTTP.get_response api
  end

  def json
    JSON.parse response.body
  end

  def initialize_itineraries
    json['itineraries'].each do |itinerary|
      item = itinerary['type'] == 'video' ? Video.new(itinerary) : Article.new(itinerary)
      item.download_file
      @itineraries << item
    end
  end

  def run
    self.initialize_itineraries

    h = HtmlGenerator.new do |g| 
      g.itineraries = @itineraries
    end

    h.generate
  end
end


# Put the production server address
SERVER = begin
           if ARGV[0] == 'development'
             if ARGV[1]
               ARGV[1]
             else
               "http://localhost:3000"
             end
           else
             "http://admin.tvopen.com.br"
           end
         end

SERIAL = begin 
           if ARGV[0] == 'development'
             "CD9AK29HYCGPAH09" 
           else
             exec "cat /proc/cpuinfo | grep Serial | cut -d' ' -f2"
           end
         end

synchronizer = Synchronizer.new do |s|
  s.serial = SERIAL
  s.server = SERVER
end.run

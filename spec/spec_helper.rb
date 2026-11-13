require 'simplecov'

SimpleCov.start do
  coverage_dir ENV.fetch('COVERAGE_DIR', 'coverage')
  track_files '{bin,lib}/**/*.rb'
  add_filter '/spec/'
  minimum_coverage 100
  minimum_coverage_by_file 100
end

require 'dotenv'
require 'fileutils'
require 'logger'
require 'stringio'
require 'tmpdir'
require_relative '../lib/synchronizer'

RSpec.configure do |config|
  config.order = :random
  config.around do |example|
    previous_content_dir = $content_dir
    Dir.mktmpdir('signaged-spec') do |directory|
      $content_dir = directory
      example.run
    end
  ensure
    $content_dir = previous_content_dir
  end
end

RSpec.describe Synchronizer do
  subject(:synchronizer) { described_class.new('https://example.test', 'device') }

  let(:items) do
    %w[video article image widget].map do |type|
      {
        'type' => type, 'url' => "https://example.test/#{type}?v=1",
        'impress_url' => 'https://example.test/impression', 'display_time' => 12,
        'audio_enabled' => true, 'checksum' => Digest::SHA512.hexdigest('media')
      }
    end
  end
  let(:cache_path) { File.join($content_dir, 'device.json') }
  let(:schedule) { { 'items' => items } }

  it 'requests the device schedule, downloads each item and caches the response' do
    uri = URI('https://example.test/api/devices/device/sync.json')
    allow(Net::HTTP).to receive(:get_response).with(uri)
      .and_return(double(body: JSON.generate(schedule)))
    items.each do |item|
      FileUtils.mkdir_p(File.join($content_dir, item.fetch('type')))
      expect(Net::HTTP).to receive(:get_response).with(URI(item.fetch('url')))
        .and_return(double(body: 'media'))
    end

    Dir.chdir($content_dir) { expect(synchronizer.sync).to eq(schedule) }
    expect(JSON.parse(File.read(cache_path))).to eq(schedule)
    expect(synchronizer.items.map(&:class)).to eq([Video, Article, Image, Widget])
    expect(synchronizer.items.map { |item| File.read(item.file_path) }).to eq(['media'] * 4)
  end

  it 'uses the cached schedule and skips media downloads when offline' do
    File.write(cache_path, JSON.generate(schedule))
    allow(Net::HTTP).to receive(:get_response).and_raise(IOError)

    expect(synchronizer.sync).to eq(schedule)
    expect(synchronizer.can_download).to be(false)
    expect(synchronizer.items.size).to eq(4)
    expect(synchronizer.items.none? { |item| File.exist?(item.file_path) }).to be(true)
  end

  it 'falls back to cache when the server response contains invalid JSON' do
    File.write(cache_path, JSON.generate(schedule))
    allow(Net::HTTP).to receive(:get_response).and_return(double(body: 'invalid'))
    expect(synchronizer.json_response).to eq(schedule)
  end

  it 'reports a missing cache' do
    expect(synchronizer.get_local_json).to be(false)
  end

  it 'logs a message for a corrupt cache' do
    File.write(cache_path, 'invalid')
    expect { expect(synchronizer.get_local_json).to be_nil }
      .to output(/Can't download JSON items/).to_stdout
  end

  { '' => '  key_mgmt=NONE', 'secret' => '  psk="secret"' }.each do |password, setting|
    it "writes the Wi-Fi configuration with #{password.empty? ? 'no password' : 'a password'}" do
      config = { 'wifi_name' => 'test-wifi', 'wifi_password' => password }
      allow(synchronizer).to receive(:json_response).and_return('items' => [], 'wifi_config' => config)
      buffer = StringIO.new
      expect(File).to receive(:open).with('/etc/wpa_supplicant/wpa_supplicant.conf', 'wb')
        .and_yield(buffer)

      synchronizer.sync
      expect(buffer.string).to eq("network={\n  ssid=\"test-wifi\"\n#{setting}\n}\n")
    end
  end
end

RSpec.describe Schedule do
  let(:items) do
    %w[video article image widget].map do |type|
      {
        'type' => type, 'url' => "https://example.test/#{type}.media",
        'impress_url' => 'https://example.test/impression', 'display_time' => 12,
        'audio_enabled' => true
      }
    end
  end
  let(:media) { described_class.parse_items(JSON.generate(items)) }

  it 'parses the supported media types and their settings in schedule order' do
    expect(media.map(&:class)).to eq([Video, Article, Image, Widget])
    expect(media.first.audio_enabled).to be(true)
    expect(media.drop(1).map(&:display_time)).to eq([12, 12, 12])
    expect(media.last.relative_file_path).to eq('/widget/widget.media')
  end

  it 'removes only obsolete files and retains generated images for articles and widgets' do
    allow(Dir).to receive(:entries).and_call_original
    downloads = '/home/pi/signaged/downloads'
    allow(File).to receive(:directory?).and_call_original
    removed = media.map do |item|
      installed = File.join(downloads, item.type)
      temp = File.join($content_dir, item.type)
      FileUtils.mkdir_p(File.join(temp, 'subdir'))
      files = [item.filename, '.gitkeep', 'obsolete']
      files << "#{item.filename}.png" if %w[article widget].include?(item.type)
      files.each { |name| File.write(File.join(temp, name), '') }
      allow(Dir).to receive(:entries).with(installed).and_return(Dir.entries(temp))
      Dir.entries(temp).each do |name|
        allow(File).to receive(:directory?).with(File.join(installed, name))
          .and_return(File.directory?(File.join(temp, name)))
      end
      File.join(installed, 'obsolete')
    end
    logger = instance_double(Logger, info: nil)
    allow(Logger).to receive(:new).with('/home/pi/signaged/logs/delete_files.log', 5, 100000)
      .and_return(logger)
    expect(FileUtils).to receive(:rm) do |paths|
      expect(paths).to match_array(removed)
    end

    described_class.cleanup_unused_files(media)
  end
end

RSpec.describe Loadable do
  let(:url) { 'https://example.test/media' }
  let(:impression) { 'https://example.test/impression' }
  let(:image) { Image.new(url, impression, 12) }

  it 'starts the impression command' do
    expect(image).to receive(:spawn).with("curl #{impression}")
    image.send_impression
  end

  it 'keeps an image that is already cached' do
    FileUtils.mkdir_p(File.dirname(image.file_path))
    File.write(image.file_path, 'cached')
    expect(Net::HTTP).not_to receive(:get_response)

    image.download
    expect(File.read(image.file_path)).to eq('cached')
  end

  it 'disables downloads for a media item after a network error' do
    expect(Net::HTTP).to receive(:get_response).once.and_raise(IOError)
    Dir.chdir($content_dir) do
      expect { image.download }.to output(/Can't download/).to_stdout
      image.download
    end
    expect(image.can_download).to be(false)
    expect(File.exist?(image.file_path)).to be(false)
  end

  it 'keeps a matching video and replaces it when the checksum differs' do
    video = Video.new(url, impression, false, Digest::SHA512.hexdigest('fresh'))
    FileUtils.mkdir_p(File.dirname(video.file_path))
    File.write(video.file_path, 'fresh')
    video.download
    expect(File.read(video.file_path)).to eq('fresh')

    File.write(video.file_path, 'stale')
    expect(Net::HTTP).to receive(:get_response).with(URI(url)).once
      .and_return(double(body: 'fresh'))
    Dir.chdir($content_dir) { video.download }
    expect(File.read(video.file_path)).to eq('fresh')
  end
end

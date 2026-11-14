require_relative '../bin/auth_unit'
require_relative '../bin/git_update'
require_relative '../bin/signaged'
require_relative '../bin/signaged_player'

RSpec.describe 'Signaged commands' do
  let(:logger) { instance_double(Logger, info: nil) }
  let(:stop_loop) { Class.new(StandardError) }
  let(:mpv) do
    %w[/usr/bin/mpv --no-config --vo=drm --sws-scaler=fast-bilinear
       --no-terminal --no-input-default-bindings]
  end
  let(:synchronizer) { instance_double(Synchronizer) }

  before do
    allow(Dotenv).to receive(:load)
    allow(Logger).to receive(:new).and_return(logger)
  end

  def run_script(command)
    yield command
    expect { command.run }.to raise_error(stop_loop)
  end

  %w[true false].each do |connect|
    it "handles CONNECT_UNIT_WIFI=#{connect}" do
      allow(ENV).to receive(:[]).with('CONNECT_UNIT_WIFI').and_return(connect)
      run_script(AuthUnit) do |receiver|
        if connect == 'true'
          expect(receiver).to receive(:`).with('/usr/local/bin/casperjs /home/tvopen/signaged/lib/auth_unit.js')
          expect(logger).to receive(:info).with('Trying to connect into unit network')
        else
          expect(logger).to receive(:info).with('No need to connect into unit network')
        end
        expect(receiver).to receive(:sleep).with(21600).and_raise(stop_loop)
      end
    end
  end

  it 'pulls the configured branch every five minutes' do
    allow(ENV).to receive(:[]).with('GIT_BRANCH').and_return('main')
    run_script(GitUpdate) do |receiver|
      expect(receiver).to receive(:system).with('/usr/bin/git -C /home/tvopen/signaged pull origin main')
      expect(receiver).to receive(:sleep).with(300).and_raise(stop_loop)
    end
  end

  it 'waits for the synchronizer to create a cache on first boot' do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('SIGNAGED_SERIAL').and_return('virtualbox')
    expect(Synchronizer).to receive(:new).with(anything, 'virtualbox').and_return(synchronizer)
    expect(synchronizer).to receive(:get_local_json).twice.and_return(false, { 'items' => [] })
    run_script(SignagedPlayer) do |receiver|
      expect(receiver).to receive(:system).with(*mpv, '--no-audio', '--image-display-duration=1', '--',
                                                File.expand_path('../assets/images/black.ppm', __dir__)).twice
      expect(receiver).to receive(:sleep).with(1).ordered
      expect(receiver).to receive(:sleep).with(1).ordered.and_raise(stop_loop)
    end
  end

  [nil, 'https://example.test'].each do |server|
    it "synchronizes with #{server || 'the default server'}" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('SERVER_NAME', 'http://staging.tvopen.com.br')
        .and_return(server || 'http://staging.tvopen.com.br')
      expect(Synchronizer).to receive(:new)
        .with(server || 'http://staging.tvopen.com.br', 'serial').and_return(synchronizer)
      expect(synchronizer).to receive(:sync).and_return('check_after' => 30)
      run_script(SignagedSync) do |receiver|
        allow(receiver).to receive(:`).and_return("serial\n")
        expect(receiver).to receive(:sleep).with(150).and_raise(stop_loop)
      end
    end

    it "plays available media with #{server || 'the default server'}" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('SERVER_NAME', 'http://staging.tvopen.com.br')
        .and_return(server || 'http://staging.tvopen.com.br')
      expect(Synchronizer).to receive(:new)
        .with(server || 'http://staging.tvopen.com.br', 'serial').and_return(synchronizer)
      items = [
        instance_double(Video, type: 'video', file_path: '/silent', audio_enabled: false),
        instance_double(Video, type: 'video', file_path: '/audio', audio_enabled: true),
        instance_double(Image, type: 'image', file_path: '/image', filename: 'image', display_time: 12)
      ]
      expect(synchronizer).to receive(:get_local_json).ordered.and_return('items' => [{}])
      allow(synchronizer).to receive(:get_local_json).and_raise(stop_loop)
      allow(Schedule).to receive(:parse_items).with('[{}]').and_return(items)
      expect(Schedule).to receive(:cleanup_unused_files).with(items)
      allow(File).to receive(:file?).and_call_original
      %w[/silent /audio /image].each { |path| allow(File).to receive(:file?).with(path).and_return(true) }
      run_script(SignagedPlayer) do |receiver|
        allow(receiver).to receive(:`).with(/cpuinfo/).and_return("serial\n")
        expect(receiver).to receive(:system).with(*mpv, '--hwdec=auto', '--framedrop=decoder+vo',
                                                  '--no-audio', '--', '/silent').ordered
        expect(receiver).to receive(:system).with(*mpv, '--hwdec=auto', '--framedrop=decoder+vo',
                                                  '--', '/audio').ordered
        expect(receiver).to receive(:system).with(*mpv, '--no-audio', '--image-display-duration=12',
                                                  '--', '/image').ordered
      end
    end
  end
end

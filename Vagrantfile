env_file = File.join(__dir__, ".env")
file_settings = {}
if File.file?(env_file)
  File.foreach(env_file) do |line|
    entry = line.strip.match(/\A\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\z/)
    next unless entry

    key, value = entry.captures
    quoted = value.match(/\A(["'])(.*?)\1\s*(?:#.*)?\z/)
    file_settings[key] = quoted ? quoted[2] : value.sub(/(?:\A|\s+)#.*/, "").rstrip
  end
end

settings = file_settings.merge(ENV.to_h)
server = ENV["SIGNAGED_SERVER"] || ENV["SERVER_NAME"] ||
         file_settings["SIGNAGED_SERVER"] || file_settings["SERVER_NAME"] || ""

Vagrant.configure("2") do |config|
  config.vm.define "default", primary: true do |ubuntu|
    ubuntu.vm.box = "bento/ubuntu-24.04"
    ubuntu.vm.box_version = "202510.26.0"
    ubuntu.vm.box_architecture = :auto
    ubuntu.vm.hostname = "signaged"
    ubuntu.vm.box_url = settings["SIGNAGED_VM_BOX_URL"] if settings["SIGNAGED_VM_BOX_URL"]
  end

  config.vm.define "raspberry-pi", autostart: false do |pi|
    pi.vm.box = "bento/debian-13"
    pi.vm.box_version = "202510.26.0"
    pi.vm.box_architecture = "arm64"
    pi.vm.hostname = "signaged-pi"
    pi.vm.box_url = settings["SIGNAGED_PI_BOX_URL"] if settings["SIGNAGED_PI_BOX_URL"]
  end

  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.provider "virtualbox" do |vb|
    vb.gui = true
    vb.memory = 3072
    vb.cpus = 2
  end

  if (archive = settings["SIGNAGED_VM_ARCHIVE"])
    config.vm.provision "file", source: archive,
                                destination: "/tmp/signaged-vm.tar.gz"
    config.vm.provision "shell", path: "support/virtualbox/provision.sh",
      env: {
        "SIGNAGED_SERVER" => server,
        "SIGNAGED_SERIAL" => settings.fetch("SIGNAGED_SERIAL", "virtualbox")
      }
  end
end

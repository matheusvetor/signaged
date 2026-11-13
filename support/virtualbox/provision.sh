#!/usr/bin/env bash
set -euo pipefail

project=/home/tvopen/signaged
: "${SIGNAGED_SERVER:=}" "${SIGNAGED_SERIAL:=virtualbox}"
if [[ ! "$SIGNAGED_SERIAL" =~ ^[a-zA-Z0-9]+$ ]]; then
    printf 'SIGNAGED_SERIAL deve conter apenas letras e números.\n' >&2
    exit 1
fi
if [[ -n "$SIGNAGED_SERVER" && ! "$SIGNAGED_SERVER" =~ ^https?://[^[:space:]#]+$ ]]; then
    printf 'SIGNAGED_SERVER deve ser uma URL HTTP ou HTTPS sem espaços ou fragmento.\n' >&2
    exit 1
fi
ruby_version=4.0.9
ruby_home="/opt/signaged/ruby-$ruby_version"
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends build-essential ca-certificates curl git \
    libssl-dev libyaml-dev libreadline-dev zlib1g-dev libffi-dev libgdbm-dev psmisc python3 kbd mpv

for unit in signaged_player signaged; do
    if [[ -f "/etc/systemd/system/$unit.service" ]]; then
        systemctl stop "$unit.service"
    fi
done
if ! id tvopen >/dev/null 2>&1; then
    useradd --create-home --home-dir /home/tvopen --shell /bin/bash tvopen
fi
install -d "$project" "$project/logs"
tar -xzf /tmp/signaged-vm.tar.gz --no-same-owner -C "$project"
install -m 0755 "$project/support/virtualbox/omxplayer" /usr/local/bin/omxplayer
for kind in video article image widget; do
    install -d "$project/downloads/$kind"
done

if ! "$ruby_home/bin/ruby" -ropenssl -e 'exit(RUBY_VERSION == ARGV.first ? 0 : 1)' "$ruby_version" 2>/dev/null; then
    build_dir=$(mktemp -d)
    trap 'rm -rf "$build_dir"' EXIT
    git clone --depth 1 --branch v20261023 https://github.com/rbenv/ruby-build.git "$build_dir/ruby-build"
    MAKE_OPTS=-j2 "$build_dir/ruby-build/bin/ruby-build" "$ruby_version" "$ruby_home"
fi
ln -sfn "$ruby_home/bin/ruby" /usr/local/bin/ruby
export PATH="$ruby_home/bin:$PATH"
gem list -i bundler -v 2.4.22 >/dev/null || gem install bundler -v 2.4.22 --no-document
(
    cd "$project"
    BUNDLE_FROZEN=true BUNDLE_WITHOUT=test bundle _2.4.22_ install
)

export RUSTUP_HOME=/opt/signaged/rustup CARGO_HOME=/opt/signaged/cargo
export PATH="$CARGO_HOME/bin:$PATH"
if ! command -v rustup >/dev/null; then
    installer=$(mktemp)
    curl -fsSL https://sh.rustup.rs -o "$installer"
    sh "$installer" -y --profile minimal --default-toolchain 1.85.0 --no-modify-path
    rm -f "$installer"
fi
make -C "$project/support/fbi-vetor" CARGO='cargo +1.85.0' test build
install -D -m 0755 "$project/support/fbi-vetor/target/release/fbi" /usr/local/libexec/fbi-vetor
install -m 0755 "$project/support/virtualbox/fbi" /usr/local/bin/fbi

demo_enabled=false
# Keep the demo available without registering a physical Raspberry Pi.
if [[ -z "$SIGNAGED_SERVER" ]]; then
    demo_enabled=true
    SIGNAGED_SERVER=http://127.0.0.1:8765
    demo=/var/lib/signaged-demo
    install -d "$demo/api/devices/$SIGNAGED_SERIAL"
    install -m 0644 "$project/assets/images/loading.png" "$demo/loading.png"
    python3 - "$demo" "$SIGNAGED_SERIAL" "$project/downloads" <<'PY'
import json
import shutil
import sys
from pathlib import Path

demo, serial, downloads = map(Path, sys.argv[1:])
schedule = {
    "check_after": 150,
    "items": [{
        "type": "image",
        "url": "http://127.0.0.1:8765/loading.png",
        "impress_url": "http://127.0.0.1:8765/",
        "display_time": 10,
    }],
}
payload = json.dumps(schedule)
(demo / "api/devices" / serial / "sync.json").write_text(payload)
(downloads / f"{serial}.json").write_text(payload)
shutil.copyfile(demo / "loading.png", downloads / "image/loading.png")
PY
    cat >/etc/systemd/system/signaged-demo.service <<'UNIT'
[Unit]
Description=Local Signaged demo schedule

[Service]
DynamicUser=yes
ExecStart=/usr/bin/python3 -m http.server 8765 --bind 127.0.0.1 --directory /var/lib/signaged-demo
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
fi

printf 'SERVER_NAME=%s\nSIGNAGED_SERIAL=%s\n' "$SIGNAGED_SERVER" "$SIGNAGED_SERIAL" >"$project/.env"
for unit in signaged signaged_player; do
    systemctl unmask "$unit.service"
    install -m 0644 "$project/services/$unit.service" "/etc/systemd/system/$unit.service"
    install -d "/etc/systemd/system/$unit.service.d"
    cat >"/etc/systemd/system/$unit.service.d/virtualbox.conf" <<UNIT
[Unit]
Wants=network-online.target
After=network-online.target

[Service]
WorkingDirectory=$project
ExecStart=
ExecStart=/usr/local/bin/ruby $project/bin/$unit.rb
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=SIGNAGED_MANAGE_WIFI=false
UNIT
done

if [[ "$demo_enabled" == true ]]; then
    cat >>/etc/systemd/system/signaged.service.d/virtualbox.conf <<'UNIT'

[Unit]
Requires=signaged-demo.service
After=signaged-demo.service
UNIT
fi

cat >>/etc/systemd/system/signaged_player.service.d/virtualbox.conf <<'UNIT'

[Unit]
Wants=signaged.service
After=signaged.service

[Service]
ExecStartPre=/usr/bin/chvt 2
UNIT

systemctl daemon-reload
if [[ "$demo_enabled" == true ]]; then
    systemctl enable --now signaged-demo.service
elif systemctl is-enabled --quiet signaged-demo.service; then
    systemctl disable --now signaged-demo.service
fi
# Keep VT 2 available to the framebuffer player.
systemctl mask --now getty@tty2.service
if [[ ! -c /dev/fb0 ]]; then
    modprobe vmwgfx || true
    udevadm settle
fi
if [[ ! -c /dev/fb0 ]]; then
    printf 'Aviso: /dev/fb0 ainda não está disponível no convidado.\n' >&2
fi
systemctl enable --now signaged.service signaged_player.service
systemctl is-active signaged.service signaged_player.service

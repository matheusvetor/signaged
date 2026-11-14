#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
for tool in vagrant VBoxManage; do
    if ! command -v "$tool" >/dev/null; then
        printf 'Instale %s no host antes de criar a VM.\n' "$tool" >&2
        exit 1
    fi
done

archive=$(mktemp "${TMPDIR:-/tmp}/signaged-vm.XXXXXX")
trap 'rm -f "$archive"' EXIT

COPYFILE_DISABLE=1 tar -czf "$archive" \
    --exclude=target --exclude=dist \
    Gemfile Gemfile.lock bin lib services assets/images/loading.png assets/images/black.ppm
export SIGNAGED_VM_ARCHIVE="$archive"
vagrant up "${1:-default}" --provider=virtualbox --provision

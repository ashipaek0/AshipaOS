#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_DEVICE="$(findmnt --noheadings --output SOURCE --target /storage)"
[[ -n "$EXPECTED_DEVICE" ]] || {
  echo "/storage is not mounted" >&2
  exit 1
}
install -d -o ashipaos -g ashipaos -m 0700 /storage/config /storage/state
install -d -o ashipaos -g ashipaos -m 0755 /storage/cache /storage/thumbnails
install -d -o ashipaos -g ashipaos -m 0750 /storage/downloads /storage/logs
install -d -o root -g root -m 0755 /storage/app
[[ -w /storage/state ]] || {
  echo "/storage/state is not writable" >&2
  exit 1
}

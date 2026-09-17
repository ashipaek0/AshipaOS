#!/usr/bin/env bash
set -Eeuo pipefail

APP=/storage/app/current/bin/ashipaos
[[ -x "$APP" ]] || {
  echo "No validated AshipaOS application slot is active" >&2
  exit 1
}
exec "$APP"

#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HANDLER="$ROOT/rootfs-overlay/usr/libexec/ashipaos-boot-status-handler"

if ! command -v busybox >/dev/null || ! command -v curl >/dev/null; then
    echo "SKIP: busybox and curl are required for host boot-status E2E"
    exit 0
fi

port=$((18080 + $$ % 1000))
tmpdir=$(mktemp -d)
server_pid=""
cleanup() {
    [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
    rm -rf "$tmpdir"
}
trap cleanup EXIT

cp "$HANDLER" "$tmpdir/handler"
chmod 0755 "$tmpdir/handler"
busybox nc -ll -p "$port" -e "$tmpdir/handler" &
server_pid=$!

for _ in {1..20}; do
    if curl --silent --show-error --fail --max-time 1 "http://127.0.0.1:$port/boot-status" >"$tmpdir/body"; then
        break
    fi
    sleep 0.1
done
cmp -s "$tmpdir/body" <(printf 'ASHIPAOS_BOOT_STATUS=OK\n') || { cat "$tmpdir/body" >&2; exit 1; }

status=$(curl --silent --output /dev/null --write-out '%{http_code}' "http://127.0.0.1:$port/not-boot-status")
[[ "$status" != 200 ]] || { echo "unsupported path returned success" >&2; exit 1; }
status=$(curl --silent --output /dev/null --write-out '%{http_code}' -X POST "http://127.0.0.1:$port/boot-status")
[[ "$status" != 200 ]] || { echo "unsupported method returned success" >&2; exit 1; }

echo "PASS: busybox nc boot-status E2E"

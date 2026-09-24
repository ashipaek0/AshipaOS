#!/usr/bin/env bash
# Validate the immutable A95X CoreELEC pin and its authorized fork.
# Hashes and digests are compared to exact values, not just their format.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIN="${1:-$ROOT/build/coreelec/pin.json}"
FORK_METADATA_FILE="${COREELEC_FORK_METADATA_FILE:-}"

mapfile -t pin_values < <(python3 - "$PIN" <<'PYEOF'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    pin = json.load(stream)

full_sha = re.compile(r"^[0-9a-f]{40}$")
sha256 = re.compile(r"^[0-9a-f]{64}$")
digest = re.compile(r"^sha256:[0-9a-f]{64}$")
source = pin["source"]
builder = pin["builder"]
base = builder["base_image"]

assert pin["schema_version"] == 1
assert source["repository"] == "https://github.com/ashipaek0/CoreELEC.git"
assert source["fork"] == {
    "full_name": "ashipaek0/CoreELEC",
    "required": True,
    "parent": "CoreELEC/CoreELEC",
}
assert source["upstream_repository"] == "https://github.com/CoreELEC/CoreELEC.git"
assert source["upstream_source_line"] == "coreelec-21"
assert source["ref"] == {"type": "tag", "value": "21.3-Omega"}
assert full_sha.fullmatch(source["commit"])
assert source["commit"] == "fc61125e8900ab0c2593a29b615980ed0cd5b939"
assert source["commit"] == source["fork_commit"] == source["upstream_commit"]
assert sha256.fullmatch(source["archive"]["sha256"])
assert source["archive"] == {
    "url": f"https://github.com/ashipaek0/CoreELEC/archive/{source['commit']}.tar.gz",
    "sha256": "c31d4d047682915190fbfc16b46134e7d0a6bb8a119edee59a31b0b2b332a73a",
}
assert builder["dockerfile"]["path"] == "tools/docker/jammy/Dockerfile"
assert sha256.fullmatch(builder["dockerfile"]["sha256"])
assert builder["dockerfile"]["sha256"] == "4f0d46fdf9709230f29e6ea8c423a292024287f653b30f67be01d567a08125a2"
assert base["tag"] == "ubuntu:jammy"
assert digest.fullmatch(base["digest"])
assert base["digest"] == "sha256:b8b6ee6aa931ecd9d0d952abc34dc0e5f7c6a30c6bb71b079fe399fde0329c02"
assert base["pinned_reference"] == "ubuntu@" + base["digest"]
assert pin["build"] == {
    "PROJECT": "Amlogic-ce",
    "DEVICE": "Amlogic-ng",
    "ARCH": "arm",
    "OFFICIAL": "yes",
}
assert pin["artifact"]["path"] == "target/CoreELEC-Amlogic-ng.arm-21.3-Omega-Generic.img.gz"

print(source["repository"])
print(source["ref"]["value"])
print(source["commit"])
print(source["fork"]["full_name"])
print(source["fork"]["parent"])
PYEOF
)

if [ "${#pin_values[@]}" -ne 5 ]; then
  echo "pin validation did not return the required source fields" >&2
  exit 1
fi
repository="${pin_values[0]}"
ref="${pin_values[1]}"
expected_commit="${pin_values[2]}"
expected_full_name="${pin_values[3]}"
expected_parent="${pin_values[4]}"

if [ -n "$FORK_METADATA_FILE" ]; then
  metadata_source="$FORK_METADATA_FILE"
else
  metadata_source="$(mktemp)"
  trap 'rm -f "$metadata_source"' EXIT
  github_token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  curl_args=(
    --fail
    --silent
    --show-error
    --header 'Accept: application/vnd.github+json'
    --output "$metadata_source"
  )
  if [ -n "$github_token" ]; then
    curl_args+=(--header "Authorization: Bearer $github_token")
  fi
  # Keep the token in curl's header handling; never print it or include it in a URL.
  curl "${curl_args[@]}" "https://api.github.com/repos/$expected_full_name"
fi

python3 - "$metadata_source" "$expected_full_name" "$expected_parent" <<'PYEOF'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    metadata = json.load(stream)
assert metadata.get("full_name") == sys.argv[2], "authorized fork identity mismatch"
assert metadata.get("fork") is True, "authorized repository is not a fork"
assert (metadata.get("parent") or {}).get("full_name") == sys.argv[3], "fork parent mismatch"
PYEOF

remote_refs="$(git ls-remote --exit-code "$repository" \
  "refs/tags/$ref" "refs/tags/$ref^{}")" || {
  echo "authorized CoreELEC fork or pinned tag is unavailable: $repository $ref" >&2
  exit 1
}

resolved_commit=""
direct_commit=""
while IFS=$'\t' read -r commit remote_ref; do
  case "$remote_ref" in
    "refs/tags/$ref^{}") resolved_commit="$commit" ;;
    "refs/tags/$ref") direct_commit="$commit" ;;
  esac
done <<<"$remote_refs"
resolved_commit="${resolved_commit:-$direct_commit}"

if [ ! "$resolved_commit" = "$expected_commit" ]; then
  echo "CoreELEC tag mismatch: expected $expected_commit, resolved ${resolved_commit:-missing}" >&2
  exit 1
fi

printf 'CoreELEC pin valid: %s %s %s\n' "$repository" "$ref" "$resolved_commit"

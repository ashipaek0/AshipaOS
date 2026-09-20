#!/usr/bin/env bash
# A95X-CE-1 STATIC: CoreELEC source and builder inputs are immutable.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIN="$ROOT/build/coreelec/pin.json"
VALIDATOR="$ROOT/build/coreelec/validate-pin.sh"

python3 - "$PIN" <<'PYEOF'
import json
import re
import sys
from pathlib import Path

pin_path = Path(sys.argv[1])
with pin_path.open(encoding="utf-8") as stream:
    pin = json.load(stream)

full_sha = re.compile(r"^[0-9a-f]{40}$")
sha256 = re.compile(r"^[0-9a-f]{64}$")
oci_digest = re.compile(r"^sha256:[0-9a-f]{64}$")

assert pin["schema_version"] == 1
source = pin["source"]
assert source["repository"] == "https://github.com/ashipaek0/CoreELEC.git"
assert source["fork"] == {
    "full_name": "ashipaek0/CoreELEC",
    "required": True,
    "parent": "CoreELEC/CoreELEC",
}
assert source["upstream_repository"] == "https://github.com/CoreELEC/CoreELEC.git"
assert source["upstream_source_line"] == "coreelec-21"
assert source["ref"]["type"] == "tag"
assert source["ref"]["value"] == "21.3-Omega"
assert full_sha.fullmatch(source["commit"])
assert source["commit"] == "fc61125e8900ab0c2593a29b615980ed0cd5b939"
assert full_sha.fullmatch(source["upstream_commit"])
assert source["fork_commit"] == source["commit"] == source["upstream_commit"]
assert source["archive"]["url"].endswith(f"/{source['commit']}.tar.gz")
assert sha256.fullmatch(source["archive"]["sha256"])
assert source["archive"]["sha256"] == "c31d4d047682915190fbfc16b46134e7d0a6bb8a119edee59a31b0b2b332a73a"

builder = pin["builder"]
assert builder["dockerfile"]["path"] == "tools/docker/jammy/Dockerfile"
assert sha256.fullmatch(builder["dockerfile"]["sha256"])
assert builder["dockerfile"]["sha256"] == "4f0d46fdf9709230f29e6ea8c423a292024287f653b30f67be01d567a08125a2"
base = builder["base_image"]
assert base["tag"] == "ubuntu:jammy"
assert base["media_type"] == "application/vnd.oci.image.index.v1+json"
assert oci_digest.fullmatch(base["digest"])
assert base["digest"] == "sha256:b8b6ee6aa931ecd9d0d952abc34dc0e5f7c6a30c6bb71b079fe399fde0329c02"
assert base["pinned_reference"] == f"ubuntu@{base['digest']}"
assert base["linux_amd64_manifest_digest"] == "sha256:281c5745f657873d78e5531fc5ba8575f46ab7769b94550ac99543f122679986"

assert pin["build"] == {
    "PROJECT": "Amlogic-ce",
    "DEVICE": "Amlogic-ng",
    "ARCH": "arm",
    "OFFICIAL": "yes",
}
artifact = pin["artifact"]
expected = "target/CoreELEC-Amlogic-ng.arm-21.3-Omega-Generic.img.gz"
assert artifact["path"] == expected
assert artifact["name"] == expected.rsplit("/", 1)[1]
assert artifact["glob"] == expected

shim = pin["jellyfin_spike"]["jellyfin_mpv_shim"]
assert shim["repository"] == "https://github.com/jellyfin/jellyfin-mpv-shim.git"
assert shim["ref"]["type"] == "tag"
assert shim["ref"]["value"] == "v3.0.0"
assert shim["commit"] == "9970b2dc4a91f0c96a9fa5a1fcecf6a69331e315"
assert full_sha.fullmatch(shim["commit"])
assert shim["archive"]["url"].endswith(f"/{shim['commit']}.tar.gz")
assert sha256.fullmatch(shim["archive"]["sha256"])
assert shim["archive"]["sha256"] == "c27b8ae2d698a152052586149b30b3125d82f9ac7695d2b32ca865ef6bd7f731"

mutable_ref_names = {"main", "master", "dev", "develop", "latest", "stable", "coreelec-21"}
assert source["ref"]["value"].lower() not in mutable_ref_names
assert shim["ref"]["value"].lower() not in mutable_ref_names

def strings(value):
    if isinstance(value, dict):
        for child in value.values():
            yield from strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from strings(child)
    elif isinstance(value, str):
        yield value

placeholder = re.compile(r"(^|[^a-z])(todo|tbd|placeholder|changeme|replace[-_ ]?me|example)([^a-z]|$)", re.I)
for value in strings(pin):
    assert value.strip(), "empty string is not an immutable pin"
    assert not placeholder.search(value), f"placeholder value: {value!r}"
PYEOF

[ -x "$VALIDATOR" ] || {
  echo "missing executable pin validator: $VALIDATOR" >&2
  exit 1
}

# GitHub API authentication must be header-only, optional locally, and never logged.
validator_text="$(<"$VALIDATOR")"
grep -Fq 'GITHUB_TOKEN:-${GH_TOKEN:-}' <<<"$validator_text"
grep -Fq 'curl_args+=(--header "Authorization: Bearer $github_token")' <<<"$validator_text"
if grep -Fq 'Authorization: Bearer ***' <<<"$validator_text"; then
  echo "validator contains a redacted Authorization header" >&2
  exit 1
fi
if grep -Eq 'echo[^\n]*(GITHUB_TOKEN|GH_TOKEN|github_token)|printf[^\n]*(GITHUB_TOKEN|GH_TOKEN|github_token)' <<<"$validator_text"; then
  echo "validator logs a GitHub token" >&2
  exit 1
fi

fake_dir="$(mktemp -d)"
trap 'rm -rf "$fake_dir"' EXIT
cat >"$fake_dir/git" <<'EOF'
#!/usr/bin/env bash
case "${FAKE_GIT_MODE:-match}" in
  match)
    printf '%s\t%s\n' 'fc61125e8900ab0c2593a29b615980ed0cd5b939' 'refs/tags/21.3-Omega'
    ;;
  mismatch)
    printf '%s\t%s\n' '0000000000000000000000000000000000000000' 'refs/tags/21.3-Omega'
    ;;
  unavailable)
    exit 2
    ;;
esac
EOF
chmod +x "$fake_dir/git"
cat >"$fake_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
: "${CURL_CAPTURE:?}"
printf '%s\n' "$@" >"$CURL_CAPTURE"
if [ "${CURL_FAIL:-0}" = 1 ]; then
  exit 22
fi
output=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then
    output="$2"
    shift 2
  else
    shift
  fi
done
cat "$CURL_METADATA" >"$output"
EOF
chmod +x "$fake_dir/curl"
cat >"$fake_dir/fork.json" <<'EOF'
{
  "full_name": "ashipaek0/CoreELEC",
  "fork": true,
  "parent": {"full_name": "CoreELEC/CoreELEC"}
}
EOF

PATH="$fake_dir:$PATH" COREELEC_FORK_METADATA_FILE="$fake_dir/fork.json" FAKE_GIT_MODE=match "$VALIDATOR" "$PIN" >/dev/null
PATH="$fake_dir:$PATH" CURL_CAPTURE="$fake_dir/curl-auth.txt" CURL_METADATA="$fake_dir/fork.json" \
  GITHUB_TOKEN='token-for-test' GH_TOKEN='should-not-win' FAKE_GIT_MODE=match \
    "$VALIDATOR" "$PIN" >"$fake_dir/auth-stdout.txt" 2>"$fake_dir/auth-stderr.txt"
grep -Fqx 'Authorization: Bearer token-for-test' "$fake_dir/curl-auth.txt"
if grep -Fq 'should-not-win' "$fake_dir/curl-auth.txt"; then
  echo "validator selected GH_TOKEN over GITHUB_TOKEN" >&2
  exit 1
fi
for output in "$fake_dir/auth-stdout.txt" "$fake_dir/auth-stderr.txt"; do
  if grep -Fq 'token-for-test' "$output"; then
    echo "validator exposed the GitHub token in $output" >&2
    exit 1
  fi
done
PATH="$fake_dir:$PATH" CURL_CAPTURE="$fake_dir/curl-unauth.txt" CURL_METADATA="$fake_dir/fork.json" \
  env -u GITHUB_TOKEN -u GH_TOKEN FAKE_GIT_MODE=match "$VALIDATOR" "$PIN" >/dev/null
if grep -Fq 'Authorization:' "$fake_dir/curl-unauth.txt"; then
  echo "validator sent an Authorization header without a token" >&2
  exit 1
fi
if PATH="$fake_dir:$PATH" CURL_CAPTURE="$fake_dir/curl-http-error.txt" CURL_METADATA="$fake_dir/fork.json" \
  CURL_FAIL=1 env -u GITHUB_TOKEN -u GH_TOKEN FAKE_GIT_MODE=match "$VALIDATOR" "$PIN" >/dev/null 2>&1; then
  echo "validator accepted a GitHub API HTTP failure" >&2
  exit 1
fi
if PATH="$fake_dir:$PATH" COREELEC_FORK_METADATA_FILE="$fake_dir/fork.json" FAKE_GIT_MODE=mismatch "$VALIDATOR" "$PIN" >/dev/null 2>&1; then
  echo "validator accepted a mismatched fork tag" >&2
  exit 1
fi
if PATH="$fake_dir:$PATH" COREELEC_FORK_METADATA_FILE="$fake_dir/fork.json" FAKE_GIT_MODE=unavailable "$VALIDATOR" "$PIN" >/dev/null 2>&1; then
  echo "validator accepted an unavailable authorized fork" >&2
  exit 1
fi
cat >"$fake_dir/wrong-parent.json" <<'EOF'
{
  "full_name": "ashipaek0/CoreELEC",
  "fork": true,
  "parent": {"full_name": "example/CoreELEC"}
}
EOF
if PATH="$fake_dir:$PATH" COREELEC_FORK_METADATA_FILE="$fake_dir/wrong-parent.json" FAKE_GIT_MODE=match "$VALIDATOR" "$PIN" >/dev/null 2>&1; then
  echo "validator accepted a fork of the wrong parent" >&2
  exit 1
fi

echo "test-coreelec-pin: PASS"

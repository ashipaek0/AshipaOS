#!/usr/bin/env bash
set -Eeuo pipefail
out=${1:?usage: capture-flathub-trust.sh OUTPUT_DIR}
readonly repofile_url=https://flathub.org/repo/flathub.flatpakrepo
readonly expected_url=https://dl.flathub.org/repo/
# Verified from the official repofile/key, with the full primary fingerprint
# cross-checked against Flatpak upstream's Flathub-key reference.
readonly expected_fingerprint=6E5C05D979C76DAF93C081354184DD4D907A7CAE
mkdir -p "$out"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl --fail --silent --show-error --location "$repofile_url" -o "$tmp/flathub.flatpakrepo"
python3 - "$tmp/flathub.flatpakrepo" "$tmp/flathub.gpg" "$expected_url" <<'PY'
import base64, configparser, pathlib, sys
source, keyfile, expected_url = sys.argv[1:]
config = configparser.ConfigParser(interpolation=None)
if not config.read(source) or not config.has_section("Flatpak Repo"):
    raise SystemExit("official Flathub repository definition is invalid")
section = config["Flatpak Repo"]
if section.get("Url", "").rstrip("/") + "/" != expected_url:
    raise SystemExit("official Flathub repository URL mismatch")
try:
    key = base64.b64decode(section["GPGKey"], validate=True)
except (KeyError, ValueError) as exc:
    raise SystemExit(f"official Flathub signing key is invalid: {exc}")
if not key:
    raise SystemExit("official Flathub signing key is empty")
pathlib.Path(keyfile).write_bytes(key)
PY
"$(dirname "$0")/validate-flatpak-key.sh" "$tmp/flathub.gpg" "$expected_fingerprint" 'Flathub Repo Signing Key <flathub@flathub.org>'
install -m 0644 "$tmp/flathub.flatpakrepo" "$out/flathub.flatpakrepo"
install -m 0644 "$tmp/flathub.gpg" "$out/flathub.gpg"
printf '%s\n' "$expected_fingerprint" > "$out/flathub-key-fingerprint.txt"
printf 'Captured authenticated Flathub trust material: %s\n' "$expected_fingerprint"

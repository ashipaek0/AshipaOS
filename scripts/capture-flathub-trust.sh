#!/usr/bin/env bash
set -Eeuo pipefail
out=${1:?usage: capture-flathub-trust.sh OUTPUT_DIR}
. "$(dirname "$0")/flathub.env"
mkdir -p "$out"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl --fail --silent --show-error --location "$FLATHUB_REPOFILE_URL" -o "$tmp/flathub.flatpakrepo"
python3 - "$tmp/flathub.flatpakrepo" "$tmp/flathub.gpg" "$FLATHUB_URL" <<'PY'
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
"$(dirname "$0")/validate-flatpak-key.sh" "$tmp/flathub.gpg" "$FLATHUB_KEY_FINGERPRINT" "$FLATHUB_KEY_IDENTITY"
install -m 0644 "$tmp/flathub.flatpakrepo" "$out/flathub.flatpakrepo"
install -m 0644 "$tmp/flathub.gpg" "$out/flathub.gpg"
printf '%s\n' "$FLATHUB_KEY_FINGERPRINT" > "$out/flathub-key-fingerprint.txt"
printf 'Captured authenticated Flathub trust material: %s\n' "$FLATHUB_KEY_FINGERPRINT"

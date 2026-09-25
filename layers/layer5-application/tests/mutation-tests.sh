#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LAUNCHER="$ROOT/layers/layer5-application/files/usr/libexec/ashipaos-jellyfin-mpv-shim"
TMP=$(mktemp -d)
# The fixture bundle is chowned to root (and briefly to another non-caller
# uid) below to prove the launcher's ownership checks are real; plain rm as
# the invoking user cannot remove those paths back out, so cleanup needs the
# same sudo elevation used to create them.
trap 'sudo rm -rf "$TMP"' EXIT

# Execute the target guard against a real invalid invocation.
rootfs="$TMP/rootfs.tar.gz"
printf 'not-a-tar' > "$rootfs"
if bash "$ROOT/layers/layer5-application/scripts/build-application.sh" "$rootfs" a95x-f3-air >/dev/null 2>&1; then
  echo 'mutation/fail-closed: incomplete invocation was accepted' >&2; exit 1
fi

# Fake NSS: resolves "ashipa" to the invoking user's own uid/gid, through the
# same getent lookup the launcher makes, so CONFIG fixtures can be built and
# validated without a real ashipa system account or root. This must be an
# actual executed getent, not a source-string check, or the launcher's real
# identity resolution would never run.
mkdir -p "$TMP/bin"
uid="$(id -u)" gid="$(id -g)"
printf '#!/bin/sh\ncase "$1" in\n  passwd) printf "ashipa:x:%s:%s::/storage:/bin/sh\\n";;\n  group) printf "ashipa:x:%s:\\n";;\nesac\n' \
  "$uid" "$gid" "$gid" >"$TMP/bin/getent"
chmod 0755 "$TMP/bin/getent"
export PATH="$TMP/bin:$PATH"

bundle="$TMP/bundle"
config="$TMP/config"
defaults="$TMP/defaults"
mkdir -p "$bundle/bin" "$defaults"
printf '#!/bin/sh\nexit 0\n' >"$bundle/bin/jellyfin-mpv-shim"
python3 - "$bundle/bin/jellyfin-mpv-shim" "$bundle/manifest.json" <<'PY'
import hashlib, json, pathlib, sys
exe = pathlib.Path(sys.argv[1])
manifest = {"schema": "ashipaos.jellyfin-mpv-shim.slot.v1", "name": "jellyfin-mpv-shim", "version": "3.0.0",
            "executable": "bin/jellyfin-mpv-shim", "sha256": hashlib.sha256(exe.read_bytes()).hexdigest(),
            "python_tag": "cp313", "abi_tag": "cp313", "platform_tag": "manylinux_2_27_aarch64",
            "dependency_status": "RESOLVED"}
pathlib.Path(sys.argv[2]).write_text(json.dumps(manifest) + "\n")
PY
printf '{"enable_gui": true}' >"$defaults/conf.json"
printf 'vo=gpu\n' >"$defaults/mpv.conf"
# Set every mode as the invoking user, THEN hand ownership to root: once
# chowned, this user can no longer chmod these paths directly (matching the
# real, root-only bundle build-application.sh produces), so mode must be
# correct first.
find "$bundle" -type d -exec chmod 0755 {} +
find "$bundle" -type f -exec chmod 0644 {} +
chmod 0755 "$bundle/bin/jellyfin-mpv-shim"
sudo chown -R 0:0 "$bundle"

run_launcher() {
  ASHIPAOS_BUNDLE="$bundle" ASHIPAOS_CONFIG="$config" ASHIPAOS_DEFAULTS="$defaults" "$1" >/dev/null 2>&1
}

# Positive path: a genuinely valid, root-owned bundle is accepted, CONFIG is
# created and seeded from DEFAULTS, and the bundle executable actually runs.
run_launcher "$LAUNCHER" || { echo 'mutation/fail-closed: a fully valid bundle was rejected' >&2; exit 1; }
[[ -d "$config" ]] || { echo 'mutation/fail-closed: launcher did not create the config directory' >&2; exit 1; }
[[ -f "$config/conf.json" && -f "$config/mpv.conf" ]] ||
  { echo 'mutation/fail-closed: launcher did not seed defaults into a fresh config directory' >&2; exit 1; }
rm -rf "$config"

# A manifest with a stale executable digest is rejected before execution.
python3 - "$bundle/manifest.json" "$TMP/manifest.json" <<'PY'
import json, pathlib, sys
value = json.loads(pathlib.Path(sys.argv[1]).read_text())
value["sha256"] = "0" * 64
pathlib.Path(sys.argv[2]).write_text(json.dumps(value) + "\n")
PY
sudo cp "$TMP/manifest.json" "$bundle/manifest.json"
sudo chown 0:0 "$bundle/manifest.json"; sudo chmod 0644 "$bundle/manifest.json"
if run_launcher "$LAUNCHER"; then
  echo 'mutation/fail-closed: stale manifest digest was accepted' >&2; exit 1
fi

# Malformed manifests (missing field, wrong schema, wrong name) fail closed.
for mutate in 'del value["python_tag"]' 'value["schema"] = "wrong"' 'value["name"] = "other"'; do
  python3 - "$bundle/manifest.json" "$TMP/manifest.json" <<PY
import json, pathlib, sys
value = json.loads(pathlib.Path(sys.argv[1]).read_text())
$mutate
pathlib.Path(sys.argv[2]).write_text(json.dumps(value) + "\n")
PY
  sudo cp "$TMP/manifest.json" "$bundle/manifest.json"
  sudo chown 0:0 "$bundle/manifest.json"; sudo chmod 0644 "$bundle/manifest.json"
  if run_launcher "$LAUNCHER"; then
    echo "mutation/fail-closed: manifest mutation ($mutate) was accepted" >&2; exit 1
  fi
done

# Restore a correct manifest for the remaining checks.
python3 - "$bundle/bin/jellyfin-mpv-shim" "$TMP/manifest.json" <<'PY'
import hashlib, json, pathlib, sys
exe = pathlib.Path(sys.argv[1])
manifest = {"schema": "ashipaos.jellyfin-mpv-shim.slot.v1", "name": "jellyfin-mpv-shim", "version": "3.0.0",
            "executable": "bin/jellyfin-mpv-shim", "sha256": hashlib.sha256(exe.read_bytes()).hexdigest(),
            "python_tag": "cp313", "abi_tag": "cp313", "platform_tag": "manylinux_2_27_aarch64",
            "dependency_status": "RESOLVED"}
pathlib.Path(sys.argv[2]).write_text(json.dumps(manifest) + "\n")
PY
sudo cp "$TMP/manifest.json" "$bundle/manifest.json"
sudo chown 0:0 "$bundle/manifest.json"; sudo chmod 0644 "$bundle/manifest.json"
run_launcher "$LAUNCHER" || { echo 'mutation/setup: restored manifest+hash was unexpectedly rejected' >&2; exit 1; }
rm -rf "$config"

# A group/world-writable executable violates the ownership/mode contract.
sudo chmod 0775 "$bundle/bin/jellyfin-mpv-shim"
if run_launcher "$LAUNCHER"; then
  echo 'mutation/fail-closed: a group-writable executable was accepted' >&2; exit 1
fi
sudo chmod 0755 "$bundle/bin/jellyfin-mpv-shim"

# A bundle executable owned by anyone other than root (e.g. the app's own
# ashipa identity tampering with what it runs) must be rejected. A fixed
# non-root uid (not the invoking user's, which may itself be root in a
# privileged CI/test environment) proves this regardless of who runs the test.
sudo chown 65534:65534 "$bundle/bin/jellyfin-mpv-shim"
if run_launcher "$LAUNCHER"; then
  echo 'mutation/fail-closed: a non-root-owned executable was accepted' >&2; exit 1
fi
sudo chown 0:0 "$bundle/bin/jellyfin-mpv-shim"
run_launcher "$LAUNCHER" || { echo 'mutation/setup: restored ownership was unexpectedly rejected' >&2; exit 1; }
rm -rf "$config"

# A pre-existing config directory with the wrong mode is rejected (the
# launcher only fixes this up on first creation, never widens it after).
mkdir -p "$config"
chmod 0755 "$config"
if run_launcher "$LAUNCHER"; then
  echo 'mutation/fail-closed: a wrongly-moded pre-existing config directory was accepted' >&2; exit 1
fi

# Ownership/mode mutant: prove the real launcher's CONFIG check is load-
# bearing by deleting it from a copy and confirming the same wrongly-moded
# directory above is then silently accepted.
mutant="$TMP/mutant-launcher"
python3 - "$LAUNCHER" "$mutant" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text()
needle = 'owned_mode "$CONFIG" "$ashipa_uid" "$ashipa_gid" 700 || error "configuration ownership or mode is invalid"'
if needle not in s:
    raise SystemExit('ownership mutation fixture missing')
pathlib.Path(sys.argv[2]).write_text(s.replace(needle, 'true'))
PY
chmod 0755 "$mutant"
if ! run_launcher "$mutant"; then
  echo 'mutation/fail-closed: ownership mutant did not change the outcome' >&2; exit 1
fi
printf 'layer5-application-mutation: PASS\n'

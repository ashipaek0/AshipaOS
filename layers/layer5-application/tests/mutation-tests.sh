#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LAUNCHER="$ROOT/layers/layer5-application/files/usr/libexec/ashipaos-jellyfin-mpv-shim"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Execute the target guard against a real invalid invocation.
rootfs="$TMP/rootfs.tar.gz"
printf 'not-a-tar' > "$rootfs"
if bash "$ROOT/layers/layer5-application/scripts/build-application.sh" "$rootfs" a95x-f3-air >/dev/null 2>&1; then
  echo 'mutation/fail-closed: incomplete invocation was accepted' >&2; exit 1
fi

# Build a structurally valid but wrongly owned slot. Mutating ownership
# validation must be observable by executing the mutated launcher, not merely
# by checking that a source string changed.
mkdir -p "$TMP/slots/A/bin" "$TMP/config"
chmod 0700 "$TMP/slots" "$TMP/slots/A" "$TMP/config"
printf '#!/bin/sh\nexit 0\n' > "$TMP/slots/A/bin/jellyfin-mpv-shim"
chmod 0755 "$TMP/slots/A/bin/jellyfin-mpv-shim"
python3 - "$TMP/slots/A/bin/jellyfin-mpv-shim" "$TMP/slots/A/manifest.json" "$TMP/active.json" <<'PY'
import hashlib, json, pathlib, sys
exe=pathlib.Path(sys.argv[1])
manifest={"schema":"ashipaos.jellyfin-mpv-shim.slot.v1","name":"jellyfin-mpv-shim","version":"3.0.0","executable":"bin/jellyfin-mpv-shim","sha256":hashlib.sha256(exe.read_bytes()).hexdigest(),"python_tag":"cp311","abi_tag":"cp311","platform_tag":"manylinux_2_27_aarch64","dependency_status":"RESOLVED"}
pathlib.Path(sys.argv[2]).write_text(json.dumps(manifest)+'\n')
pathlib.Path(sys.argv[3]).write_text('{"slot":"A","version":"3.0.0"}\n')
PY
chmod 0600 "$TMP/active.json" "$TMP/slots/A/manifest.json"
# Supply a target-like ashipa identity for the host-only fixture.
mkdir -p "$TMP/bin"
# Use the caller's real uid/gid so the fixture files are "owned by ashipa".
uid="$(id -u)" gid="$(id -g)"
printf '#!/bin/sh\ncase "$1" in passwd) printf "ashipa:x:%s:%s::/storage:/bin/sh\\n";; group) printf "ashipa:x:%s:\\n";; esac\n' \
  "$uid" "$gid" "$gid" > "$TMP/bin/getent"
chmod 0755 "$TMP/bin/getent"
export PATH="$TMP/bin:$PATH"
# Malformed selectors, mismatched versions, and absent fallback bundles all fail closed.
for selector in '{"slot":"C","version":"3.0.0"}' '{"slot":"A","version":"9.9.9"}' '{not-json'; do
  printf '%s\n' "$selector" > "$TMP/bad-active.json"
  if ASHIPAOS_ACTIVE="$TMP/bad-active.json" ASHIPAOS_SLOTS="$TMP/slots" ASHIPAOS_CONFIG="$TMP/config" ASHIPAOS_IMMUTABLE="$TMP/missing" "$LAUNCHER" >/dev/null 2>&1; then
    echo 'mutation/fail-closed: malformed or mismatched selector was accepted' >&2; exit 1
  fi
done
# A manifest with a stale executable digest is rejected before execution.
python3 - "$TMP/slots/A/manifest.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); value=json.loads(p.read_text()); value['sha256']='0'*64; p.write_text(json.dumps(value)+'\n')
PY
printf '{"slot":"A","version":"3.0.0"}\n' > "$TMP/active.json"
if ASHIPAOS_ACTIVE="$TMP/active.json" ASHIPAOS_SLOTS="$TMP/slots" ASHIPAOS_CONFIG="$TMP/config" ASHIPAOS_IMMUTABLE="$TMP/missing" "$LAUNCHER" >/dev/null 2>&1; then
  echo 'mutation/fail-closed: stale manifest digest was accepted' >&2; exit 1
fi
python3 - "$TMP/slots/A/bin/jellyfin-mpv-shim" "$TMP/slots/A/manifest.json" <<'PY'
import hashlib, json, pathlib, sys
exe, manifest = map(pathlib.Path, sys.argv[1:])
data=json.loads(manifest.read_text()); data['sha256']=hashlib.sha256(exe.read_bytes()).hexdigest(); manifest.write_text(json.dumps(data)+'\n')
PY
# A group-writable executable violates the slot ownership/mode contract: the
# real launcher must refuse it, and a launcher with that check removed must
# accept it. Both outcomes are required for the check to be proven live.
chmod 0775 "$TMP/slots/A/bin/jellyfin-mpv-shim"
run_launcher() {
  ASHIPAOS_ACTIVE="$TMP/active.json" ASHIPAOS_SLOTS="$TMP/slots" ASHIPAOS_CONFIG="$TMP/config" \
    ASHIPAOS_IMMUTABLE="$TMP/missing" "$1" >/dev/null 2>&1
}
if run_launcher "$LAUNCHER"; then
  echo 'mutation/fail-closed: wrongly-moded executable was accepted' >&2; exit 1
fi
mutant="$TMP/mutant-launcher"
python3 - "$LAUNCHER" "$mutant" <<'PY'
import pathlib, sys
s=pathlib.Path(sys.argv[1]).read_text()
needle='[[ "$actual_owner" == "$owner" && "$actual_group" == "$group" && "$actual_mode" == 755 ]] || return 1'
if needle not in s: raise SystemExit('ownership mutation fixture missing')
pathlib.Path(sys.argv[2]).write_text(s.replace(needle, 'true'))
PY
chmod 0755 "$mutant"
run_launcher "$mutant" || { echo 'mutation/fail-closed: ownership mutant did not change the outcome' >&2; exit 1; }
printf 'layer5-application-mutation: PASS\n'

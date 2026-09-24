#!/usr/bin/env bash
# Layer 5 STATIC: bundle tooling, committed lock and launcher stay consistent.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LAYER="$ROOT/layers/layer5-application"
SCRIPT="$LAYER/scripts/build-application.sh"
TOOL="$LAYER/scripts/jellyfin-bundle.py"
LAUNCHER="$LAYER/files/usr/libexec/ashipaos-jellyfin-mpv-shim"
LOCK="$LAYER/config/dependencies.lock.json"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -x "$SCRIPT" && -x "$TOOL" && -x "$LAUNCHER" ]] || fail "layer 5 scripts must be executable"
bash -n "$SCRIPT" "$LAUNCHER"
python3 -B -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$TOOL"

# The committed lock must pass the same validation CI applies before download.
python3 -B - "$TOOL" "$LOCK" <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("jellyfin_bundle", sys.argv[1])
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
lock = tool.load_lock(pathlib.Path(sys.argv[2]))
for item in lock["artifacts"]:
    bad = dict(item, filename=item["filename"].replace("aarch64", "x86_64").replace("py3-none-any", "cp311-cp311-win_amd64"))
    bad["url"] = item["url"].rsplit("/", 1)[0] + "/" + bad["filename"]
    try:
        tool.check_artifact(bad)
    except ValueError:
        continue
    raise SystemExit(f"foreign-platform wheel accepted: {bad['filename']}")
# The application source pin must agree with the CoreELEC-track pin record.
import json
shim = json.load(open(pathlib.Path(sys.argv[2]).parents[3] / "build/coreelec/pin.json"))["jellyfin_spike"]["jellyfin_mpv_shim"]
if (shim["commit"], shim["archive"]["url"], shim["archive"]["sha256"]) != (tool.SOURCE_COMMIT, tool.SOURCE_URL, tool.SOURCE_SHA256):
    raise SystemExit("jellyfin-mpv-shim pin differs between pin.json and jellyfin-bundle.py")
PY

# build-application.sh writes exactly the manifest fields the launcher accepts.
for field in schema name version executable sha256 python_tag abi_tag platform_tag dependency_status; do
    grep -q "\"$field\"" "$SCRIPT" || fail "build-application.sh does not write manifest field $field"
    grep -q "\"$field\"" "$LAUNCHER" || fail "launcher does not validate manifest field $field"
done
grep -q 'dependency_status.*RESOLVED' "$LAUNCHER" || fail "launcher requires a RESOLVED bundle"
! grep -q 'python3-mpv' "$SCRIPT" "$LAUNCHER" || fail "Debian python3-mpv must not be used"
! grep -Eq 'pip install|urllib|curl|wget' "$SCRIPT" || fail "bundle installation must not access the network"
printf 'layer5-application-static: PASS\n'

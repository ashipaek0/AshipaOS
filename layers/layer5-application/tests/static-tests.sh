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
    bad = dict(item, filename=item["filename"].replace("aarch64", "x86_64").replace("py3-none-any", "cp313-cp313-win_amd64"))
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
# Boot-to-app contract: the image boots straight into the shim.
UNIT="$LAYER/files/etc/systemd/system/ashipaos-jellyfin-mpv-shim.service"
DEFAULTS="$LAYER/files/usr/share/ashipaos/jellyfin-mpv-shim"
python3 -B - "$UNIT" "$DEFAULTS" "$LAUNCHER" <<'PY' || fail "Jellyfin MPV Shim boot service contract"
import configparser, json, pathlib, re, sys
unit_path, defaults, launcher = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]).read_text()
unit = configparser.ConfigParser(strict=False, interpolation=None)
unit.optionxform = str
unit.read(unit_path)
svc = unit["Service"]
assert svc["User"] == "ashipa" and svc["ExecStart"] == "/usr/libexec/ashipaos-jellyfin-mpv-shim"
assert unit["Install"]["WantedBy"] == "multi-user.target"
assert svc["TTYPath"] == "/dev/tty1" and svc["StandardInput"] == "tty"
assert "getty@tty1.service" in unit["Unit"]["Conflicts"]
assert int(unit["Unit"]["StartLimitBurst"]) > 0 and svc["Restart"] == "always"
assert {"video", "render", "audio", "input"} <= set(svc["SupplementaryGroups"].split())
env = dict(l.strip().split("=", 2)[1:] for l in open(unit_path) if l.startswith("Environment="))
config_dir = env["XDG_CONFIG_HOME"] + "/jellyfin-mpv-shim"
assert f'CONFIG="${{ASHIPAOS_CONFIG:-{config_dir}}}"' in launcher, "unit and launcher disagree on the config dir"
assert config_dir in svc["ReadWritePaths"].split() and "/storage/apps/jellyfin-mpv-shim" in svc["ReadWritePaths"].split()
conf = json.loads((defaults / "conf.json").read_text())
assert conf["enable_gui"] and conf["browser_fullscreen"] and conf["fullscreen"] and not conf["mpv_idle_quit"]
mpv = dict(l.split("=", 1) for l in (defaults / "mpv.conf").read_text().split("\n") if l and not l.startswith("#"))
assert mpv["vo"] == "gpu" and mpv["gpu-context"] == "drm"
assert not {"idle", "force-window", "fullscreen"} & set(mpv), "mpv.conf must not override shim-managed options"
PY
grep -q 'multi-user.target.wants/$SERVICE' "$SCRIPT" || fail "build-application.sh must enable the shim service"
grep -q 'ln -sfn /dev/null "$ROOTFS/etc/systemd/system/getty@tty1.service"' "$SCRIPT" || fail "tty1 getty must be masked"
printf 'layer5-application-static: PASS\n'

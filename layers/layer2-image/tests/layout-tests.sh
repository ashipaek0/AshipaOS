#!/usr/bin/env bash
set -Eeuo pipefail

LAYER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$LAYER_DIR/scripts/build-image.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

command -v sfdisk >/dev/null || {
    echo "SKIP: sfdisk is unavailable" >&2
    exit 77
}

expected_repo_root="$(git -C "$LAYER_DIR" rev-parse --show-toplevel)"
resolved_repo_root="$("$BUILD_SCRIPT" --print-repo-root)"
[[ "$resolved_repo_root" == "$expected_repo_root" ]] || {
    echo "Layer 2 resolved repository root incorrectly: $resolved_repo_root" >&2
    exit 1
}
[[ "$(git -C "$resolved_repo_root" rev-parse HEAD)" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Layer 2 repository root cannot provide a full commit SHA" >&2
    exit 1
}

image="$TMP_DIR/layout.img"
"$BUILD_SCRIPT" --layout-only "$image"
sfdisk --verify "$image" >/dev/null

layout="$(sfdisk --json "$image")"
python3 - "$layout" <<'PY'
import json, sys
table = json.loads(sys.argv[1])["partitiontable"]
parts = table["partitions"]
assert table["label"] == "gpt"
assert len(parts) == 2
assert parts[0]["start"] == 2048
assert parts[0]["size"] == 256 * 2048
assert parts[1]["start"] == 2048 + 256 * 2048
assert parts[1]["size"] == 3584 * 2048
PY

a95x_image="$TMP_DIR/a95x-layout.img"
"$BUILD_SCRIPT" --layout-only "$a95x_image" a95x-f3-air
sfdisk --verify "$a95x_image" >/dev/null
a95x_layout="$(sfdisk --json "$a95x_image")"
python3 - "$a95x_layout" <<'PY'
import json, sys
table = json.loads(sys.argv[1])["partitiontable"]
parts = table["partitions"]
assert table["label"] == "dos"
assert len(parts) == 2
assert parts[0]["start"] == 8192
assert parts[0]["size"] == 256 * 2048
assert parts[1]["start"] == 8192 + 256 * 2048
assert parts[1]["size"] == 3584 * 2048
PY

bad_config="$TMP_DIR/bad.yaml"
sed 's/image_size_mb: 4096/image_size_mb: 100/' "$LAYER_DIR/config/image-config.yaml" >"$bad_config"
if ASHIPAOS_IMAGE_CONFIG="$bad_config" "$BUILD_SCRIPT" --validate 2>/dev/null; then
    echo "invalid oversized partition layout was accepted" >&2
    exit 1
fi

missing_rootfs="$TMP_DIR/does-not-exist.tar.gz"
evidence_file="$LAYER_DIR/evidence/build-evidence.json"
evidence_before="missing"
[[ ! -f "$evidence_file" ]] || evidence_before="$(sha256sum "$evidence_file")"
if GITHUB_WORKSPACE="$TMP_DIR" RUNNER_TEMP="$TMP_DIR" \
    "$BUILD_SCRIPT" "$missing_rootfs" x86_64 >/dev/null 2>&1; then
    echo "missing rootfs was accepted" >&2
    exit 1
fi
evidence_after="missing"
[[ ! -f "$evidence_file" ]] || evidence_after="$(sha256sum "$evidence_file")"
[[ "$evidence_after" == "$evidence_before" ]] || {
    echo "failed build emitted false PASS evidence" >&2
    exit 1
}

echo "Layer 2 layout tests passed"

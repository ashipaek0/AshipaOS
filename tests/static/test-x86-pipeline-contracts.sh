#!/usr/bin/env bash
# Regression contracts for the x86_64 pre-image pipeline.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$ROOT/.github/workflows/build-images.yml"
full="$ROOT/build/scripts/full-build.sh"
python3 - "$ROOT" "$workflow" "$full" <<'PY'
from pathlib import Path
import sys
root, workflow_path, full_path = map(Path, sys.argv[1:])
workflow = Path(workflow_path).read_text()
full = Path(full_path).read_text()
x86 = workflow[workflow.index('  build-x86_64:'):workflow.index('  build-a95x-f3-air:')]
assert 'bash tests/vm/test-boot-x86_64-fake.sh' in workflow
for script in ('layer3-init/scripts/build-init.sh', 'layer5-settingsd/scripts/build-settingsd.sh', 'layer6-ota/scripts/build-ota.sh', 'layer4-services/scripts/build-services.sh'):
    text = (root / 'layers' / script).read_text()
    assert 'LAYER_DIR/../..' in text, f'{script} has incorrect repo root resolution'
assert 'build-init.sh output/rootfs-x86_64.tar.gz x86_64' in x86
assert 'build-settingsd.sh output/rootfs-x86_64.tar.gz x86_64' in x86
assert 'build-ota.sh output/rootfs-x86_64.tar.gz x86_64' in x86
assert x86.index('build-ota.sh output/rootfs-x86_64.tar.gz x86_64') < x86.index('Build Layer 2 (Disk Image)')
assert 'Generate SBOM' in x86 and x86.index('Generate SBOM') < x86.index('Sign Artefacts')
for item in ('output/ota/manifest.json', 'output/ota/manifest.json.sha256', 'output/sbom.json.sig', 'output/sbom.json.sha256'):
    assert item in x86, f'missing artifact upload: {item}'
assert 'if [[ -n "${{ secrets.GPG_PRIVATE_KEY }}" ]]' in workflow
assert 'sudo --preserve-env=SUDO_UID,SUDO_GID \\\n            bash layers/layer5-application/scripts/build-application.sh' in x86
assert 'ROOTFS_DIR' in (root / 'layers/layer5-application/scripts/build-application.sh').read_text()
assert '"$ROOTFS"' not in (root / 'layers/layer5-application/scripts/build-application.sh').read_text().split('ROOTFS_DIR=', 1)[1].split('mkdir -p', 1)[0]
assert full.index('build_layer6 "$rootfs_tar" "$target"') < full.index('build_layer2 "$rootfs_tar" "$target"')
assert 'run_privileged bash "$LAYERS_DIR/layer5-application/scripts/build-application.sh" "$rootfs" x86_64' in full
print('test-x86-pipeline-contracts: PASS')
PY

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/rootfs/etc" "$TMP/rootfs/usr/lib/systemd"
printf 'root:x:0:0:root:/root:/bin/sh\n' > "$TMP/rootfs/etc/passwd"
printf 'root:x:0:\n' > "$TMP/rootfs/etc/group"
printf 'base\n' > "$TMP/rootfs/etc/base"
tar -C "$TMP/rootfs" -czf "$TMP/rootfs.tar.gz" .
ASHIPAOS_OUTPUT="$TMP/output" OUTPUT_DIR="$TMP/output" bash "$ROOT/layers/layer3-init/scripts/build-init.sh" "$TMP/rootfs.tar.gz" x86_64
OUTPUT_DIR="$TMP/output" bash "$ROOT/layers/layer5-settingsd/scripts/build-settingsd.sh" "$TMP/rootfs.tar.gz" x86_64
OUTPUT_DIR="$TMP/output" bash "$ROOT/layers/layer6-ota/scripts/build-ota.sh" "$TMP/rootfs.tar.gz" x86_64
mkdir -p "$TMP/extracted"
tar -xzf "$TMP/rootfs.tar.gz" -C "$TMP/extracted"
test -f "$TMP/extracted/etc/hostname"
test -f "$TMP/extracted/etc/dbus-1/system.d/com.ashipaos.settings.conf"
test -f "$TMP/extracted/etc/ota/manifest.json"
test -f "$TMP/output/ota/manifest.json"
test -f "$TMP/output/ota/manifest.json.sha256"
printf 'test-x86-pipeline-rootfs-integration: PASS\n'

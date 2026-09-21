#!/usr/bin/env bash
# Full x86_64 build orchestration: Layers 1-10.
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAYERS_DIR="$ROOT_DIR/layers"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/output}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/output/work}"
export OUTPUT_DIR WORK_DIR
log() { echo "[full-build] $(date '+%Y-%m-%d %H:%M:%S') $*"; }
die() { echo "[full-build] ERROR: $*" >&2; exit 1; }
run_privileged() { if [[ $EUID -eq 0 ]]; then "$@"; else command -v sudo >/dev/null || die 'sudo is required'; sudo --preserve-env=SUDO_UID,SUDO_GID -- "$@"; fi; }
usage() { cat <<EOF
Usage: $(basename "$0") [--skip-l1] [--rootfs PATH] [--version VER] x86_64
EOF
}
build_layer1() { bash "$LAYERS_DIR/layer1-rootfs/scripts/build-rootfs.sh" amd64 "$1" x86_64; }
build_display() { bash "$LAYERS_DIR/layer3-display/scripts/build-display.sh" "$1" x86_64; }
build_services() { bash "$LAYERS_DIR/layer4-services/scripts/build-services.sh" "$1" x86_64; }
build_application() { run_privileged bash "$LAYERS_DIR/layer5-application/scripts/build-application.sh" "$1" x86_64 "$OUTPUT_DIR/evidence/layer5-dependency-resolution.json"; }
build_init() { bash "$LAYERS_DIR/layer3-init/scripts/build-init.sh" "$1" x86_64; }
build_settings() { bash "$LAYERS_DIR/layer5-settingsd/scripts/build-settingsd.sh" "$1" x86_64; }
build_ota() { bash "$LAYERS_DIR/layer6-ota/scripts/build-ota.sh" "$1" x86_64; }
main() {
  local skip_l1=false existing_rootfs='' version=''
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; return 0;;
      --skip-l1) skip_l1=true; shift;;
      --rootfs) existing_rootfs="$2"; shift 2;;
      --version) version="$2"; shift 2;;
      -*) die "Unknown option: $1";;
      *) break;;
    esac
  done
  [[ "${1:-}" == x86_64 && $# -eq 1 ]] || die 'x86_64 is the only supported target'
  export VERSION="${version:-$(date +%Y%m%d)}"
  mkdir -p "$OUTPUT_DIR" "$WORK_DIR" "$OUTPUT_DIR/evidence"
  local rootfs="$OUTPUT_DIR/rootfs-x86_64.tar.gz"
  if [[ -n "$existing_rootfs" ]]; then rootfs="$existing_rootfs"; elif [[ "$skip_l1" == true && -f "$rootfs" ]]; then :; else build_layer1 "$rootfs"; fi
  [[ -f "$rootfs" ]] || die "Rootfs not found: $rootfs"
  build_display "$rootfs"
  build_services "$rootfs"
  build_application "$rootfs"
  build_init "$rootfs"
  build_settings "$rootfs"
  build_ota "$rootfs"
  bash "$LAYERS_DIR/layer2-image/scripts/build-image.sh" "$rootfs" x86_64
  bash "$LAYERS_DIR/layer10-release/scripts/build-10-release.sh" x86_64
  bash "$ROOT_DIR/scripts/ci-generate-sbom.sh" "$OUTPUT_DIR/sbom.json"
  bash "$ROOT_DIR/scripts/ci-sign-artefacts.sh" "$OUTPUT_DIR/images" "$OUTPUT_DIR/ota"
  echo 'full-build: PASS'
}
main "$@"

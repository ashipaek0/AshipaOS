#!/usr/bin/env bash
# Single entry point for every static gate. Used by BOTH pr.yml and
# build-images.yml so the two can never drift apart again.
#
# Runs everything, collects failures, prints a summary, exits non-zero if any
# gate failed. (A plain `for ...; do bash ...; done` under `bash -e` stops at
# the first failure and hides the rest.)
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Layers that exist only as x86_64-era test stubs on this branch: they have a
# tests/ dir but no scripts/ (and sometimes no config/), so their own static
# test can never pass. Skipped explicitly and visibly; delete the dirs to retire.
DEFERRED_LAYERS=(layer3-init layer7-hal layer8-media layer9-input)

repo_tests=(
  tests/static/test-rootfs-ownership.sh
  tests/static/test-signing-safety.sh
  tests/static/test-shell-scripts.sh
  tests/static/test-workflow-files.sh
  tests/static/test-target-schema.sh
  tests/static/test-no-box-hardcoding.sh
  tests/static/test-coreelec-pin.sh
  tests/static/test-coreelec-contract.sh
  tests/static/test-coreelec-ce2a.sh
  tests/static/test-coreelec-ce2a-bind-paths.sh
)

failed=()
passed=0
run_gate() {
  local name="$1"; shift
  printf '::group::%s\n' "$name"
  if "$@"; then
    printf '::endgroup::\nPASS  %s\n' "$name"
    passed=$((passed + 1))
  else
    printf '::endgroup::\n::error::FAIL  %s\n' "$name"
    failed+=("$name")
  fi
}

is_deferred() {
  local layer="$1" d
  for d in "${DEFERRED_LAYERS[@]}"; do [[ "$d" == "$layer" ]] && return 0; done
  return 1
}

for t in "${repo_tests[@]}"; do
  run_gate "$t" bash "$t"
done

for dir in layers/layer*/; do
  layer="$(basename "$dir")"
  [[ -f "${dir}tests/static-tests.sh" ]] || continue
  if is_deferred "$layer"; then
    printf 'SKIP  %s (deferred: no scripts/ on the A95X branch)\n' "$layer"
    continue
  fi
  run_gate "$layer static tests" bash "${dir}tests/static-tests.sh"
done

printf '\n=== static gates: %d passed, %d failed ===\n' "$passed" "${#failed[@]}"
if ((${#failed[@]})); then
  printf ' - %s\n' "${failed[@]}"
  exit 1
fi

#!/usr/bin/env bash
# Single entry point for every static gate. Used by BOTH pr.yml and
# build-images.yml so the two can never drift apart.
#
# Runs everything, collects failures, prints a summary, and exits non-zero if
# any gate failed (a plain loop under `bash -e` would stop at the first one).
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

gates=(
  tests/static/test-shell-scripts.sh
  tests/static/test-workflow-files.sh
  tests/static/test-target-schema.sh
  tests/static/test-no-box-hardcoding.sh
  tests/static/test-rootfs-ownership.sh
  tests/static/test-signing-safety.sh
  tests/static/test-boot-status.sh
  tests/static/test-ir-keymap.sh
  tests/e2e/test-boot-status.sh
  tests/e2e/test-boot-success.sh
  tests/e2e/test-storage-grow.sh
  tests/static/test-coreelec-pin.sh
  tests/static/test-coreelec-contract.sh
  tests/static/test-coreelec-ce2a.sh
  tests/negative/test-coreelec-ce2a.sh
  layers/layer1-rootfs/tests/static-tests.sh
  layers/layer2-image/tests/static-tests.sh
  layers/layer2-image/tests/layout-tests.sh
  layers/layer2-image/tests/image-content-tests.sh
  layers/layer5-application/tests/static-tests.sh
  layers/layer5-application/tests/mutation-tests.sh
  layers/layer10-release/tests/static-tests.sh
)

failed=()
passed=0
for gate in "${gates[@]}"; do
  printf '::group::%s\n' "$gate"
  if bash "$gate"; then
    printf '::endgroup::\nPASS  %s\n' "$gate"
    passed=$((passed + 1))
  else
    printf '::endgroup::\n::error::FAIL  %s\n' "$gate"
    failed+=("$gate")
  fi
done

# A test that exists but is not listed above would silently never run.
# (test-coreelec-ce2a-bind-paths.sh is run by test-coreelec-ce2a.sh.)
not_gates=(tests/static/run-static.sh tests/static/test-coreelec-ce2a-bind-paths.sh)
while IFS= read -r test; do
  printf '%s\n' "${gates[@]}" "${not_gates[@]}" | grep -Fxq "$test" || { printf '::error::UNLISTED  %s\n' "$test"; failed+=("$test (unlisted)"); }
done < <(find layers tests -name '*.sh' -path '*tests*' | sort)

printf '\n=== static gates: %d passed, %d failed ===\n' "$passed" "${#failed[@]}"
if ((${#failed[@]})); then
  printf ' - %s\n' "${failed[@]}"
  exit 1
fi

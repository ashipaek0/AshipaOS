#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

awk '
  function check_job() {
    if (calls_release && !has_ripgrep) {
      printf "%s: job %s invokes build-release.sh without declaring ripgrep\n", FILENAME, job > "/dev/stderr"
      failed = 1
    }
  }
  /^  [A-Za-z0-9_-]+:$/ {
    check_job()
    job = $1
    sub(/:$/, "", job)
    calls_release = 0
    has_ripgrep = 0
  }
  /build\/scripts\/build-release\.sh/ { calls_release = 1 }
  /(^|[[:space:]])ripgrep([[:space:]]|$)/ { has_ripgrep = 1 }
  ENDFILE { check_job() }
  END { exit failed }
' "$ROOT"/.github/workflows/*.yml

echo "test-build-release-dependencies: PASS"

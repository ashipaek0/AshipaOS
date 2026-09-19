#!/usr/bin/env bash
# Regression: relative output arguments must be normalized before Docker calls.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BUILD=$ROOT/build/coreelec/ce2a-build.sh
python3 - "$BUILD" <<'PY'
import pathlib, sys
text=pathlib.Path(sys.argv[1]).read_text()
workspace=text.index('WORKSPACE=$(realpath "$2")')
evidence=text.index('EVIDENCE=$(realpath "$3")')
first_docker=text.index('docker build')
assert workspace < first_docker and evidence < first_docker
assert '"$WORKSPACE/source:/build"' in text
assert 'docker build' in text and '"$WORKSPACE/source"' in text
# Mutation guard: removing normalization must make the contract fail.
mutated=text.replace('WORKSPACE=$(realpath "$2")', 'WORKSPACE=$2').replace('EVIDENCE=$(realpath "$3")', 'EVIDENCE=$3')
assert 'WORKSPACE=$(realpath "$2")' not in mutated
assert 'EVIDENCE=$(realpath "$3")' not in mutated
print('test-coreelec-ce2a-bind-paths: PASS')
PY

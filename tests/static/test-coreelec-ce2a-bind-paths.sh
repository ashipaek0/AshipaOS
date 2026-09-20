#!/usr/bin/env bash
# Regression: relative output arguments must be normalized before Docker calls.
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BUILD=$ROOT/build/coreelec/ce2a-build.sh
python3 - "$BUILD" <<'PY'
import hashlib, pathlib, sys
text=pathlib.Path(sys.argv[1]).read_text()
workspace=text.index('WORKSPACE=$(realpath "$2")')
evidence=text.index('EVIDENCE=$(realpath "$3")')
commit=text.index('commit=${v[0]}')
first_docker=text.index('docker build')
assert workspace < first_docker and evidence < first_docker
extract=text.index('tar --extract')
mirror=text.index('DISTRO_MIRROR=')
assert extract < mirror < first_docker, 'mirror override must be generated after extraction and before Docker build'
expected_mirror='DISTRO_MIRROR="https://ftp.gnu.org/gnu http://sources.coreelec.org http://sources.libreelec.tv/mirror"'
assert hashlib.sha256((expected_mirror + chr(10)).encode()).hexdigest() == 'f44cc8d2b261293b9498d6296263d0ecb59cd02bad735c75b3cdadb9b687ac7d'
assert expected_mirror in text, 'mirror override ordering/content changed'
assert 'mirror_options_sha256=$(sha256sum' in text, 'mirror override hash must be recorded'
assert 'mirror_options_content=' in text, 'mirror override content must be recorded'
assert text.count(expected_mirror) == 1, 'mirror override must have one deterministic definition'
assert 'http://sources.coreelec.org' in text and 'http://sources.libreelec.tv/mirror' in text
assert text.index('archive_sha=${v[1]}') < mirror
assert text.index('docker_sha=${v[2]}') < mirror
assert 'echo "$archive_sha  $archive" | sha256sum --check --status' in text, 'source archive hash verification must remain intact'
assert 'sha256sum "$WORKSPACE/source/$dockerfile_rel"' in text, 'Dockerfile hash verification must remain intact'
assert commit < text.index('docker run'), 'Docker run must use the parsed pinned commit'
assert '"$WORKSPACE/source:/build"' in text
assert 'docker build' in text and '"$WORKSPACE/source"' in text
run=text[text.index('docker run'):text.index('\ncount=', text.index('docker run'))]
custom_hash='-e CUSTOM_GIT_HASH="$commit"'
assert run.count(custom_hash) == 1, 'Docker run must propagate the parsed pinned commit'
assert '--user docker' in run, 'Docker build must use the pinned non-root docker user'
assert '--user 0:0' not in run, 'Docker build must not run as root'
assert '--user root' not in run, 'Docker build must not run as root'
assert '-w /build' in run, 'Docker build must set /build as the working directory'
chmod='chmod -R a+rwX "$WORKSPACE/source"'
assert chmod in text and text.index(chmod) < text.index('docker run'), 'source tree must be writable before Docker run'
assert 'chmod -R a+rX "$WORKSPACE/source/target"' in text, 'runner-readable target output is required'
assert 'mirror_options_sha256' in text[text.index('ce2a-build-result.txt'):]
assert 'mirror_options_content' in text[text.index('ce2a-build-result.txt'):]
# Mutation guard: removing normalization or pinned provenance must fail the contract.
mutated=text.replace('WORKSPACE=$(realpath "$2")', 'WORKSPACE=$2').replace('EVIDENCE=$(realpath "$3")', 'EVIDENCE=$3')
assert 'WORKSPACE=$(realpath "$2")' not in mutated
assert 'EVIDENCE=$(realpath "$3")' not in mutated
mutated_hash=run.replace(custom_hash, '-e CUSTOM_GIT_HASH="$archive_sha"')
assert custom_hash not in mutated_hash
print('test-coreelec-ce2a-bind-paths: PASS')
PY

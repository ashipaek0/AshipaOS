#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
# A truncated archive must fail closure validation rather than pass on a listing.
mkdir -p "$tmp/initrd"; printf '#!/bin/sh\n' > "$tmp/initrd/init"; chmod +x "$tmp/initrd/init"
(cd "$tmp/initrd" && find . -print | cpio -o -H newc 2>/dev/null | gzip -9 > "$tmp/bad-initramfs.gz")
! "$ROOT/scripts/check-initramfs-closure.sh" "$tmp/bad-initramfs.gz"
# ISO catalog, FAT, GRUB, and manifest negatives run against complete fixtures
# in test-iso-relations.py, even when xorriso is unavailable on this host.
# Exact Flatpak lock verification must reject wrong and missing commits.
python3 - "$tmp/lock.json" <<'PY'
import json,sys
json.dump({'refs':[{'ref':'app/example/x86_64/stable','commit':'a'*64}]},open(sys.argv[1],'w'))
PY
printf 'app/example/x86_64/stable\t%s\n' "$(printf 'b%.0s' {1..64})" > "$tmp/wrong.tsv"; ! "$ROOT/scripts/verify-flatpak-lock.py" "$tmp/lock.json" "$tmp/wrong.tsv"
: > "$tmp/missing.tsv"; ! "$ROOT/scripts/verify-flatpak-lock.py" "$tmp/lock.json" "$tmp/missing.tsv"
printf 'app/example/x86_64/stable\t%s\n' "$(printf 'a%.0s' {1..64})" > "$tmp/good.tsv"; "$ROOT/scripts/verify-flatpak-lock.py" "$tmp/lock.json" "$tmp/good.tsv"
printf 'app/example/x86_64/stable\t%s\napp/extra/x86_64/stable\t%s\n' "$(printf 'a%.0s' {1..64})" "$(printf 'c%.0s' {1..64})" > "$tmp/extra.tsv"; ! "$ROOT/scripts/verify-flatpak-lock.py" "$tmp/lock.json" "$tmp/extra.tsv"
python3 - "$tmp/duplicate-lock.json" <<'PY'
import json,sys
json.dump({'refs':[{'ref':'app/example/x86_64/stable','commit':'a'*64},{'ref':'app/example/x86_64/stable','commit':'b'*64}]},open(sys.argv[1],'w'))
PY
printf 'app/example/x86_64/stable\t%s\n' "$(printf 'a%.0s' {1..64})" > "$tmp/good.tsv"; ! "$ROOT/scripts/verify-flatpak-lock.py" "$tmp/duplicate-lock.json" "$tmp/good.tsv"
printf 'app/example/x86_64/stable\t%s\napp/example/x86_64/stable\t%s\n' "$(printf 'a%.0s' {1..64})" "$(printf 'a%.0s' {1..64})" > "$tmp/duplicate-installed.tsv"; ! "$ROOT/scripts/verify-flatpak-lock.py" "$tmp/lock.json" "$tmp/duplicate-installed.tsv"
printf 'app/example/x86_64/stable\t%s\nmalformed-row\n' "$(printf 'a%.0s' {1..64})" > "$tmp/malformed.tsv"; ! "$ROOT/scripts/verify-flatpak-lock.py" "$tmp/lock.json" "$tmp/malformed.tsv"
printf 'app/example/x86_64/stable\t\n' > "$tmp/empty-commit.tsv"; ! "$ROOT/scripts/verify-flatpak-lock.py" "$tmp/lock.json" "$tmp/empty-commit.tsv"
python3 - "$tmp/malformed-lock.json" <<'PY'
import json,sys
json.dump({'refs':[{'ref':'app/example/x86_64/stable','commit':'not-a-commit'}]},open(sys.argv[1],'w'))
PY
! "$ROOT/scripts/verify-flatpak-lock.py" "$tmp/malformed-lock.json" "$tmp/good.tsv"
# A matching nonsensical ref is invalid in both lock and installed TSV.
python3 - "$tmp/nonsense-lock.json" <<'PY'
import json,sys
json.dump({'refs':[{'ref':'nonsense','commit':'a'*64}]},open(sys.argv[1],'w'))
PY
printf 'nonsense\t%s\n' "$(printf 'a%.0s' {1..64})" > "$tmp/nonsense.tsv"
! "$ROOT/scripts/verify-flatpak-lock.py" "$tmp/nonsense-lock.json" "$tmp/nonsense.tsv"
python3 - "$tmp/lock.json" <<'PY'
import json,sys
json.dump({'refs':[{'ref':'app/example/x86_64/stable','commit':'a'*64}]},open(sys.argv[1],'w'))
PY
printf 'app/example/x86_64/stable\t%s\napp/example/unknown/stable\t%s\n' "$(printf 'a%.0s' {1..64})" "$(printf 'a%.0s' {1..64})" > "$tmp/bad-arch.tsv"
! "$ROOT/scripts/verify-flatpak-lock.py" "$tmp/lock.json" "$tmp/bad-arch.tsv"
printf '%s\n' 'validator negative cases and Flatpak lock negatives: PASS'

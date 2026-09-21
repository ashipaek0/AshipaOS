#!/usr/bin/env bash
set -Eeuo pipefail
image="${1:?usage: image-content-tests.sh IMAGE}"
[[ -f "$image" ]]
sfdisk --verify "$image" >/dev/null
fdisk -l "$image" | grep -q 'EFI System'
printf '%s\n' 'x86_64 image content contract: PASS'

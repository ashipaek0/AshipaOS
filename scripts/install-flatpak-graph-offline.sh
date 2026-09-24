#!/usr/bin/env bash
set -Eeuo pipefail
repo=${1:?exported OSTree repo}; rows=${2:?locked ref rows}
[[ -d "$repo" && "${repo%/}" == */.ostree/repo && -s "$rows" ]] || exit 1
while IFS=$'\t' read -r ref commit; do
  [[ -n "$ref" && -n "$commit" ]] || exit 1
  flatpak --user install --noninteractive --no-related --sideload-repo="$repo" flathub "$ref"
done < "$rows"

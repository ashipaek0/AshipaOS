#!/usr/bin/env bash
# Print installed refs as full "kind/name/arch/branch<TAB>commit" rows.
# `flatpak list` only offers the short ref and a truncated active commit.
set -Eeuo pipefail
mode=${1:?usage: list-installed-flatpaks.sh --user|--system}
[[ "$mode" == --user || "$mode" == --system ]] || { echo 'invalid Flatpak installation mode' >&2; exit 2; }
listing=$(flatpak "$mode" list --columns=ref)
while IFS= read -r ref; do
  [[ -n "$ref" ]] || continue
  full=$(flatpak "$mode" info --show-ref "$ref")
  commit=$(flatpak "$mode" info --show-commit "$ref")
  printf '%s\t%s\n' "$full" "$commit"
done <<<"$listing"

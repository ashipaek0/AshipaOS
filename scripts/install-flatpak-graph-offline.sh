#!/usr/bin/env bash
# Install every locked ref from a create-usb export in one transaction. Callers
# run this inside a network namespace so nothing can come from the network.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/flathub.env"
mode=${1:?usage: install-flatpak-graph-offline.sh --user|--system SIDELOAD_REPO REF...}
repo=${2:?expected exported .ostree/repo}; shift 2
[[ "$mode" == --user || "$mode" == --system ]] || { echo 'invalid Flatpak installation mode' >&2; exit 2; }
[[ -d "$repo" && "${repo%/}" == */.ostree/repo ]] || { echo 'expected exported .ostree/repo directory' >&2; exit 2; }
(($#)) || { echo 'no locked refs to install' >&2; exit 2; }
# Every related ref create-usb exported is itself locked, so skip related-ref
# resolution rather than let Flatpak look for extras that cannot exist offline.
flatpak "$mode" install --noninteractive --no-related --sideload-repo="$repo" "$FLATHUB_REMOTE" "$@"

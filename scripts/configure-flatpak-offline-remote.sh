#!/usr/bin/env bash
set -Eeuo pipefail
mode=${1:?expected --user or --system}
action=${2:?expected restore}
[[ "$mode" == --user || "$mode" == --system ]] || { echo 'invalid Flatpak installation mode' >&2; exit 2; }
readonly remote=flathub
readonly collection=org.flathub.Stable
readonly official_url=https://dl.flathub.org/repo/
readonly pinned_fingerprint=6E5C05D979C76DAF93C081354184DD4D907A7CAE
flatpak_args=("$mode")
repo_config() {
  if [[ "$mode" == --user ]]; then
    printf '%s/flatpak/repo' "${XDG_DATA_HOME:-$HOME/.local/share}"
  else
    printf '%s' "${FLATPAK_SYSTEM_REPO:-/var/lib/flatpak/repo}"
  fi
}
get_config() {
  ostree config --repo="$(repo_config)" --group "remote \"$remote\"" get "$1"
}
check_key() {
  local key=$1 fingerprint=$2
  [[ "$fingerprint" == "$pinned_fingerprint" ]] || { echo 'Flathub signing key fingerprint is not the reviewed pin' >&2; return 1; }
  "$(dirname "$0")/validate-flatpak-key.sh" "$key" "$pinned_fingerprint" 'Flathub Repo Signing Key <flathub@flathub.org>'
}
case "$action" in
  restore)
    repo=${3:?expected Flatpak installation repo path}
    key=${4:?expected pinned Flathub GPG key}
    fingerprint=${5:?expected pinned Flathub fingerprint}
    check_key "$key" "$fingerprint"
    [[ -d "$repo" && "$(repo_config)" == "$repo" ]] || { echo 'Flatpak repo path mismatch' >&2; exit 1; }
    rm -f "$(repo_config)/${remote}.trustedkeys.gpg"
    flatpak "${flatpak_args[@]}" remote-modify --url="$official_url" --gpg-import="$key" --gpg-verify --collection-id="$collection" --enable "$remote"
    # Flatpak CLI versions may leave summary verification true when a collection
    # ID is supplied. It is ignored for collection refs, and upstream documents
    # false as the collection-remote setting to permit peer-to-peer distribution.
    ostree config --repo="$(repo_config)" --group "remote \"$remote\"" set gpg-verify-summary false
    [[ "$(get_config url)" == "$official_url" ]] || { echo 'Flathub URL restoration failed' >&2; exit 1; }
    [[ "$(get_config collection-id)" == "$collection" ]] || { echo 'Flathub collection ID restoration failed' >&2; exit 1; }
    [[ "$(get_config gpg-verify)" == true && "$(get_config gpg-verify-summary)" == false ]] || { echo 'Flathub collection remote verification state is invalid' >&2; exit 1; }
    check_key "$(repo_config)/${remote}.trustedkeys.gpg" "$pinned_fingerprint"
    ;;
  *) echo 'expected restore' >&2; exit 2 ;;
esac

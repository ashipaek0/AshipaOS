#!/usr/bin/env bash
# Add, or re-pin, the Flathub remote with the official URL, collection ID and
# only the pinned signing key, then verify the resulting configuration.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/flathub.env"
mode=${1:?usage: configure-flathub-remote.sh --user|--system KEY_FILE}
key=${2:?usage: configure-flathub-remote.sh --user|--system KEY_FILE}
[[ "$mode" == --user || "$mode" == --system ]] || { echo 'invalid Flatpak installation mode' >&2; exit 2; }
if [[ "$mode" == --user ]]; then
  repo=${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/repo
else
  repo=${FLATPAK_SYSTEM_DIR:-/var/lib/flatpak}/repo
fi
check_key() { "$here/validate-flatpak-key.sh" "$1" "$FLATHUB_KEY_FINGERPRINT" "$FLATHUB_KEY_IDENTITY"; }
get_config() { ostree config --repo="$repo" --group "remote \"$FLATHUB_REMOTE\"" get "$1"; }
check_key "$key"
remotes=$(flatpak "$mode" remotes --columns=name)
if grep -Fqx "$FLATHUB_REMOTE" <<<"$remotes"; then
  # Replace, rather than extend, any previously imported keyring.
  rm -f "$repo/$FLATHUB_REMOTE.trustedkeys.gpg"
  flatpak "$mode" remote-modify --url="$FLATHUB_URL" --gpg-import="$key" --gpg-verify \
    --collection-id="$FLATHUB_COLLECTION_ID" --enable "$FLATHUB_REMOTE"
else
  flatpak "$mode" remote-add --gpg-import="$key" --collection-id="$FLATHUB_COLLECTION_ID" \
    "$FLATHUB_REMOTE" "$FLATHUB_URL"
fi
[[ "$(get_config url)" == "$FLATHUB_URL" ]] || { echo 'Flathub URL verification failed' >&2; exit 1; }
[[ "$(get_config collection-id)" == "$FLATHUB_COLLECTION_ID" ]] || { echo 'Flathub collection ID verification failed' >&2; exit 1; }
# Flatpak itself rewrites gpg-verify-summary to true whenever it saves the
# remote (every install or update), so require that rather than fight it.
[[ "$(get_config gpg-verify)" == true && "$(get_config gpg-verify-summary)" == true ]] || { echo 'Flathub signature verification is not fully enabled' >&2; exit 1; }
check_key "$repo/$FLATHUB_REMOTE.trustedkeys.gpg"

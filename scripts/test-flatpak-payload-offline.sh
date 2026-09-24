#!/usr/bin/env bash
# Install the locked create-usb export into a scratch user installation with no
# network access, through the pinned Flathub remote, and verify the exact graph.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/flathub.env"
: "${HOME_ROOT:=$PWD/.flatpak-test}"
repo="$PWD/out/flatpak-repo/.ostree/repo"
[[ -d "$repo" && -s out/flatpak-lock.json && -s out/flathub.gpg ]] || { echo 'run build-flatpak-payload.sh first' >&2; exit 1; }
# Flatpak refuses user installations as root, and an unprivileged process
# cannot create a network namespace: sudo creates it, setpriv drops back to us.
(( $(id -u) != 0 )) || { echo 'run as the unprivileged build user, not root' >&2; exit 1; }
rm -rf "$HOME_ROOT"; mkdir -p "$HOME_ROOT"/{home,data,config,cache}
export HOME="$HOME_ROOT/home" XDG_DATA_HOME="$HOME_ROOT/data" XDG_CONFIG_HOME="$HOME_ROOT/config" XDG_CACHE_HOME="$HOME_ROOT/cache"
"$here/configure-flathub-remote.sh" --user "$PWD/out/flathub.gpg"
refs_text=$(python3 "$here/flatpak-lock-refs.py" out/flatpak-lock.json)
mapfile -t refs <<<"$refs_text"
sudo -n unshare -n setpriv --reuid="$(id -u)" --regid="$(id -g)" --init-groups -- \
  env HOME="$HOME" XDG_DATA_HOME="$XDG_DATA_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" PATH="$PATH" \
  "$here/install-flatpak-graph-offline.sh" --user "$repo" "${refs[@]}"
"$here/list-installed-flatpaks.sh" --user > "$HOME_ROOT/installed.tsv"
python3 "$here/verify-flatpak-lock.py" out/flatpak-lock.json "$HOME_ROOT/installed.tsv"
flatpak --user info "$APP_ID" >/dev/null
printf 'not a key' > "$HOME_ROOT/wrong-key.gpg"
if "$here/configure-flathub-remote.sh" --user "$HOME_ROOT/wrong-key.gpg"; then
  echo 'wrong Flathub key unexpectedly accepted' >&2; exit 1
fi
python3 - out/flatpak-lock.json "$HOME_ROOT/wrong-commits.tsv" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); rows=[f"{r['ref']}\t{'0'*64}" for r in x['refs']]
open(sys.argv[2],'w').write('\n'.join(rows)+'\n')
PY
if python3 "$here/verify-flatpak-lock.py" out/flatpak-lock.json "$HOME_ROOT/wrong-commits.tsv"; then
  echo 'wrong installed commits unexpectedly accepted' >&2; exit 1
fi
remote_config() { ostree config --repo="$XDG_DATA_HOME/flatpak/repo" --group "remote \"$FLATHUB_REMOTE\"" get "$1"; }
[[ "$(remote_config url)" == "$FLATHUB_URL" && "$(remote_config gpg-verify)" == true && "$(remote_config gpg-verify-summary)" == true ]] \
  || { echo 'Flathub remote changed during offline install' >&2; exit 1; }
printf '%s\n' 'offline Flatpak graph: PASS'

#!/usr/bin/env bash
set -Eeuo pipefail
APP=com.github.iwalton3.jellyfin-mpv-shim; : "${HOME_ROOT:=$PWD/.flatpak-test}"
repo="$PWD/out/flatpak-repo/.ostree/repo"; [[ -d "$repo" && -s out/flatpak-lock.json ]]
[[ -s out/flathub.gpg && -s out/flathub-key-fingerprint.txt && -s out/flathub.flatpakrepo ]]
export repo HOME_ROOT
rm -rf "$HOME_ROOT"; mkdir -p "$HOME_ROOT"/{home,data,config,cache}
export HOME="$HOME_ROOT/home" XDG_DATA_HOME="$HOME_ROOT/data" XDG_CONFIG_HOME="$HOME_ROOT/config" XDG_CACHE_HOME="$HOME_ROOT/cache"
flatpak remote-add --user --if-not-exists --gpg-import="$PWD/out/flathub.gpg" --collection-id=org.flathub.Stable flathub https://dl.flathub.org/repo/
flatpak remote-modify --user --gpg-verify --collection-id=org.flathub.Stable flathub
python3 - out/flatpak-lock.json > "$HOME_ROOT/locked-refs" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert x['collection_id']=='org.flathub.Stable'; assert x['refs']; print('\n'.join(f"{r['ref']}\t{r['commit']}" for r in x['refs']))
PY
helper=$(cd "$(dirname "$0")" && pwd)/install-flatpak-graph-offline.sh
if unshare -n true 2>/dev/null; then
  unshare -n "$helper" "$repo" "$HOME_ROOT/locked-refs"
elif command -v sudo >/dev/null && sudo -n true 2>/dev/null; then
  sudo -n --preserve-env=HOME,XDG_DATA_HOME,XDG_CONFIG_HOME,XDG_CACHE_HOME unshare -n "$helper" "$repo" "$HOME_ROOT/locked-refs"
else echo 'cannot establish network-isolated namespace' >&2; exit 1; fi
flatpak --user list --columns=ref,commit > "$HOME_ROOT/installed.tsv"
python3 "$(dirname "$0")/verify-flatpak-lock.py" out/flatpak-lock.json "$HOME_ROOT/installed.tsv"
flatpak --user info "$APP" >/dev/null
"$(dirname "$0")/configure-flatpak-offline-remote.sh" --user restore "$XDG_DATA_HOME/flatpak/repo" "$PWD/out/flathub.gpg" "$(<out/flathub-key-fingerprint.txt)"
if "$(dirname "$0")/configure-flatpak-offline-remote.sh" --user restore "$XDG_DATA_HOME/flatpak/repo" "$PWD/out/flathub.gpg" 0000000000000000000000000000000000000000; then
  echo 'wrong Flathub fingerprint unexpectedly accepted' >&2; exit 1
fi
printf 'not a key' > "$HOME_ROOT/wrong-key.gpg"
if "$(dirname "$0")/configure-flatpak-offline-remote.sh" --user restore "$XDG_DATA_HOME/flatpak/repo" "$HOME_ROOT/wrong-key.gpg" "$(<out/flathub-key-fingerprint.txt)"; then
  echo 'wrong Flathub key unexpectedly accepted' >&2; exit 1
fi
python3 - out/flatpak-lock.json "$HOME_ROOT/wrong-commits.tsv" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); rows=[f"{r['ref']}\t{'0'*64}" for r in x['refs']]
open(sys.argv[2],'w').write('\n'.join(rows)+'\n')
PY
if python3 "$(dirname "$0")/verify-flatpak-lock.py" out/flatpak-lock.json "$HOME_ROOT/wrong-commits.tsv"; then
  echo 'wrong installed commits unexpectedly accepted' >&2; exit 1
fi
[[ "$(ostree config --repo="$XDG_DATA_HOME/flatpak/repo" --group 'remote "flathub"' get url)" == https://dl.flathub.org/repo/ ]]
[[ "$(ostree config --repo="$XDG_DATA_HOME/flatpak/repo" --group 'remote "flathub"' get gpg-verify)" == true ]]
[[ "$(ostree config --repo="$XDG_DATA_HOME/flatpak/repo" --group 'remote "flathub"' get gpg-verify-summary)" == false ]]
printf '%s\n' 'offline Flatpak graph: PASS'

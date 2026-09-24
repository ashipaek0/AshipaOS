#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/work/out/flatpak-repo/.ostree/repo" "$tmp/bin"
printf 'fixture key\n' > "$tmp/work/out/flathub.gpg"
python3 - "$tmp/work/out/flatpak-lock.json" <<'PY'
import json,sys
json.dump({'collection_id':'org.flathub.Stable','app':'com.github.iwalton3.jellyfin-mpv-shim','refs':[{'ref':'app/com.github.iwalton3.jellyfin-mpv-shim/x86_64/stable','commit':'a'*64},{'ref':'runtime/example/x86_64/stable','commit':'b'*64}]},open(sys.argv[1],'w'))
PY
# Flatpak refuses user installations as root, so the fixture runs as uid 1000
# even when the suite itself runs as root.
cat > "$tmp/bin/id" <<'SH'
#!/usr/bin/env bash
case "$1" in -u|-g) echo 1000;; *) exec /usr/bin/id "$@";; esac
SH
cat > "$tmp/bin/sudo" <<'SH'
#!/usr/bin/env bash
[[ "$1" == -n ]] || exit 1; shift
exec "$@"
SH
cat > "$tmp/bin/unshare" <<'SH'
#!/usr/bin/env bash
[[ "$1" == -n ]] || exit 1; shift
NETWORK_ISOLATED=1 exec "$@"
SH
cat > "$tmp/bin/setpriv" <<'SH'
#!/usr/bin/env bash
[[ "$1" == --reuid=1000 && "$2" == --regid=1000 && "$3" == --init-groups && "$4" == -- ]] || exit 1
shift 4
PRIVILEGES_DROPPED=1 exec "$@"
SH
cat > "$tmp/bin/flatpak" <<'SH'
#!/usr/bin/env bash
set -e
config=$XDG_DATA_HOME/flatpak/repo/config
case " $* " in
 *' remotes '*) [[ -f "$config" ]] && printf 'flathub\n' || true;;
 *' remote-add '*)
   mkdir -p "$(dirname "$config")"
   printf '[remote "flathub"]\nurl=https://dl.flathub.org/repo/\ngpg-verify=true\ngpg-verify-summary=true\ncollection-id=org.flathub.Stable\n' > "$config"
   printf 'fixture key\n' > "$(dirname "$config")/flathub.trustedkeys.gpg"
   ;;
 *' remote-modify '*) echo 'unexpected remote-modify of a fresh remote' >&2; exit 1;;
 *' install '*)
   [[ "${NETWORK_ISOLATED:-}" == 1 && "${PRIVILEGES_DROPPED:-}" == 1 ]] || { echo 'unprivileged network-isolated install required' >&2; exit 2; }
   [[ "$*" == *'--no-related'* && "$*" == *'--sideload-repo='*/.ostree/repo* ]] || { echo 'sideload install required' >&2; exit 2; }
   python3 - "$config" <<'PY'
import configparser,sys
p=configparser.ConfigParser(interpolation=None); p.read(sys.argv[1]); remote=p['remote "flathub"']
assert remote['url']=='https://dl.flathub.org/repo/'
assert remote.getboolean('gpg-verify')
assert remote['collection-id']=='org.flathub.Stable'
PY
   # One transaction: every locked ref follows the remote name.
   args=("$@"); for ((i=0; i<${#args[@]}; i++)); do [[ "${args[$i]}" == flathub ]] && break; done
   printf '%s\n' "${args[@]:i+1}" >> "$XDG_DATA_HOME/installed"
   echo x >> "$XDG_DATA_HOME/transactions"
   ;;
 *' list '*) sed -E 's#^(app|runtime)/##' "$XDG_DATA_HOME/installed";;
 *' info '*--show-ref*) grep -E "^(app|runtime)/${*: -1}\$" "$XDG_DATA_HOME/installed";;
 *' info '*--show-commit*) case "${*: -1}" in *mpv-shim*) printf 'a%.0s' {1..64};; *) printf 'b%.0s' {1..64};; esac; echo;;
 *' info '*) exit 0;;
 *) exit 1;;
esac
SH
cat > "$tmp/bin/ostree" <<'SH'
#!/usr/bin/env bash
python3 - "$@" <<'PY'
import configparser,sys
args=sys.argv[1:]; repo=next(a.split('=',1)[1] for a in args if a.startswith('--repo=')); group=args[args.index('--group')+1]
p=configparser.ConfigParser(interpolation=None); p.read(repo+'/config')
if 'set' in args: p.set(group,args[-2],args[-1]); p.write(open(repo+'/config','w'))
else: print(p.get(group,args[-1]))
PY
SH
cat > "$tmp/bin/gpg" <<'SH'
#!/usr/bin/env bash
file=${*: -1}; [[ -s "$file" && "$(<"$file")" == 'fixture key' ]] || exit 1
printf '%s\n' 'pub:::::::::' 'fpr:::::::::6E5C05D979C76DAF93C081354184DD4D907A7CAE:' 'uid:::::::::Flathub Repo Signing Key <flathub@flathub.org>:'
SH
chmod +x "$tmp/bin/"*
(cd "$tmp/work" && PATH="$tmp/bin:$PATH" HOME_ROOT="$tmp/test-home" "$root/scripts/test-flatpak-payload-offline.sh")
[[ $(wc -l < "$tmp/test-home/data/installed") == 2 ]]
[[ $(wc -l < "$tmp/test-home/data/transactions") == 1 ]]
printf '%s\n' 'offline Flatpak unprivileged sideload mock: PASS'

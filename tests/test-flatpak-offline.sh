#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/work/out/flatpak-repo/.ostree/repo" "$tmp/bin"
printf 'fixture key\n' > "$tmp/work/out/flathub.gpg"
printf '%s\n' 6E5C05D979C76DAF93C081354184DD4D907A7CAE > "$tmp/work/out/flathub-key-fingerprint.txt"
printf '[Flatpak Repo]\nUrl=https://dl.flathub.org/repo/\n' > "$tmp/work/out/flathub.flatpakrepo"
python3 - "$tmp/work/out/flatpak-lock.json" <<'PY'
import json,sys
json.dump({'collection_id':'org.flathub.Stable','app':'com.github.iwalton3.jellyfin-mpv-shim','refs':[{'ref':'app/com.github.iwalton3.jellyfin-mpv-shim/x86_64/stable','commit':'a'*64},{'ref':'runtime/example/x86_64/stable','commit':'b'*64}]},open(sys.argv[1],'w'))
PY
cat > "$tmp/bin/unshare" <<'SH'
#!/usr/bin/env bash
[[ "$1" == -n ]] || exit 1; shift
[[ "$1" == true ]] && exit 1
[[ -n "${HOME:-}" && -n "${XDG_DATA_HOME:-}" && "${2:-}" == */.ostree/repo && -d "$2" ]] || exit 1
export NETWORK_ISOLATED=1
"$@"
SH
cat > "$tmp/bin/sudo" <<'SH'
#!/usr/bin/env bash
[[ "$1" == -n ]] || exit 1; shift
[[ "$1" == true ]] && exit 0
[[ "$1" == --preserve-env=HOME,XDG_DATA_HOME,XDG_CONFIG_HOME,XDG_CACHE_HOME ]] || exit 1
shift; env -u BASH_FUNC_install_all%% "$@"
SH
cat > "$tmp/bin/flatpak" <<'SH'
#!/usr/bin/env bash
set -e
config=${FLATPAK_SYSTEM_REPO_CONFIG:-$XDG_DATA_HOME/flatpak/repo/config}
case " $* " in
 *' remote-add '*)
   mkdir -p "$(dirname "$config")"
   printf '[remote "flathub"]\nurl=https://dl.flathub.org/repo/\ngpg-verify=true\ngpg-verify-summary=true\ncollection-id=org.flathub.Stable\n' > "$config"
   printf 'fixture key\n' > "$(dirname "$config")/flathub.trustedkeys.gpg"
   ;;
 *' remote-modify '*)
   python3 - "$config" "$@" <<'PY'
import configparser,sys,shutil
path=sys.argv[1]; args=sys.argv[2:]; p=configparser.ConfigParser(interpolation=None); p.read(path); r='remote "flathub"'
for a in args:
 if a.startswith('--url='): p.set(r,'url',a.split('=',1)[1])
 if a=='--no-gpg-verify': p.set(r,'gpg-verify','false'); p.set(r,'gpg-verify-summary','false')
 if a=='--gpg-verify': p.set(r,'gpg-verify','true'); p.set(r,'gpg-verify-summary','true')
 if a.startswith('--collection-id='): p.set(r,'collection-id',a.split('=',1)[1])
 if a.startswith('--gpg-import='): shutil.copyfile(a.split('=',1)[1],path.rsplit('/',1)[0]+'/flathub.trustedkeys.gpg')
with open(path,'w') as f:p.write(f)
PY
   ;;
 *' install '*)
   [[ "${NETWORK_ISOLATED:-}" == 1 && "$*" == *'--sideload-repo='* ]] || { echo 'network-isolated sideload required' >&2; exit 2; }
   python3 - "$config" <<'PY'
import configparser,sys
p=configparser.ConfigParser(interpolation=None); p.read(sys.argv[1]); remote=p['remote "flathub"']
assert remote['url']=='https://dl.flathub.org/repo/'
assert remote.getboolean('gpg-verify')
assert remote['collection-id']=='org.flathub.Stable'
PY
   printf '%s\n' "${*: -1}" >> "$XDG_DATA_HOME/installed"
   ;;
 *' list '*) while IFS= read -r ref; do case "$ref" in *mpv-shim*) printf '%s\t%s\n' "$ref" "$(printf 'a%.0s' {1..64})";; *) printf '%s\t%s\n' "$ref" "$(printf 'b%.0s' {1..64})";; esac; done < "$XDG_DATA_HOME/installed";;
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
[[ -f "$tmp/test-home/data/installed" ]]
[[ $(wc -l < "$tmp/test-home/data/installed") == 2 ]]
printf '%s\n' 'offline Flatpak remote lifecycle mock: PASS'

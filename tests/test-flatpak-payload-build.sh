#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/work"
export FLATPAK_CALL_LOG="$tmp/flatpak-calls.log"
: > "$FLATPAK_CALL_LOG"
cat > "$tmp/bin/flatpak" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
# Reject unsupported options before matching any supported option.
for arg in "$@"; do
  if [[ "$arg" == --show-runtime-commit ]]; then
    echo 'unsupported --show-runtime-commit' >&2
    exit 2
  fi
done
case " $* " in
  *' remotes '*) exit 0 ;;
  *' remote-add '*)
    for arg in "$@"; do
      if [[ "$arg" == --gpg-import=* ]]; then
        install -D "${arg#--gpg-import=}" "$XDG_DATA_HOME/flatpak/repo/flathub.trustedkeys.gpg"
      fi
    done ;;
  *' install '*) exit 0 ;;
  *' info '*--show-ref*) printf '%s\n' 'app/com.github.iwalton3.jellyfin-mpv-shim/x86_64/stable' ;;
  *' info '*--show-runtime*) printf '%s\n' 'org.freedesktop.Platform/x86_64/25.08' ;;
  *' info '*--show-commit*)
    printf '%s\n' "$*" >> "$FLATPAK_CALL_LOG"
    case "$*" in *' org.freedesktop.Platform/x86_64/25.08'*) printf '%064d\n' 2;; *) printf '%064d\n' 1;; esac ;;
  *' create-usb --help '*) exit 0 ;;
  *' create-usb '*) mkdir -p "$3/.ostree/repo" ;;
  *) echo "unexpected flatpak invocation: $*" >&2; exit 1 ;;
esac
SH
cat > "$tmp/bin/ostree" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
case "$1" in
  refs)
    [[ "$*" == *'--collections'* && "$*" == *'--revision'* ]] || { echo 'collection refs and revisions required' >&2; exit 2; }
    refs=(
      'app/com.github.iwalton3.jellyfin-mpv-shim/x86_64/stable'
      'runtime/org.freedesktop.Platform/x86_64/25.08'
      'runtime/org.freedesktop.Platform.Locale/x86_64/25.08'
    )
    for n in "${!refs[@]}"; do
      printf '(org.flathub.Stable, %s)\t%064d\n' "${refs[$n]}" "$((n+1))"
    done
    ;;
  config)
    case "${*: -1}" in
      url) echo https://dl.flathub.org/repo/ ;;
      collection-id) echo org.flathub.Stable ;;
      gpg-verify|gpg-verify-summary) echo true ;;
      *) exit 1 ;;
    esac ;;
  *) exit 1;;
esac
SH
# Serve a fixture Flathub repofile and key so the test never touches the network.
cat > "$tmp/bin/curl" <<'SH'
#!/usr/bin/env bash
[[ "$*" == *https://flathub.org/repo/flathub.flatpakrepo* ]] || exit 22
out=$(sed -n 's/.*-o \([^ ]*\).*/\1/p' <<<"$*")
printf '[Flatpak Repo]\nUrl=https://dl.flathub.org/repo/\nGPGKey=%s\n' "$(printf 'fixture key\n' | base64 -w0)" > "$out"
SH
cat > "$tmp/bin/gpg" <<'SH'
#!/usr/bin/env bash
file=${*: -1}; [[ -s "$file" && "$(<"$file")" == 'fixture key' ]] || exit 1
printf '%s\n' 'pub:::::::::' 'fpr:::::::::6E5C05D979C76DAF93C081354184DD4D907A7CAE:' 'uid:::::::::Flathub Repo Signing Key <flathub@flathub.org>:'
SH
chmod +x "$tmp/bin/"*
# Mutation check: the unsupported option must fail on the mock itself.
if PATH="$tmp/bin:$PATH" flatpak info --user --show-runtime-commit com.example.App; then
  echo 'mock accepted unsupported --show-runtime-commit' >&2
  exit 1
fi
(cd "$tmp/work" && PATH="$tmp/bin:$PATH" bash "$root/scripts/build-flatpak-payload.sh")
python3 - "$tmp/work/out/flatpak-lock.json" "$FLATPAK_CALL_LOG" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
assert len(x['refs']) == 3, x
assert {r['collection_id'] for r in x['refs']} == {'org.flathub.Stable'}
expected_refs = [
 'app/com.github.iwalton3.jellyfin-mpv-shim/x86_64/stable',
 'runtime/org.freedesktop.Platform/x86_64/25.08',
 'runtime/org.freedesktop.Platform.Locale/x86_64/25.08']
assert [r['ref'] for r in x['refs']] == expected_refs
assert [r['commit'] for r in x['refs']] == [f'{n:064d}' for n in range(1,4)]
calls=open(sys.argv[2]).read().splitlines()
assert any('--show-commit org.freedesktop.Platform/x86_64/25.08' in call for call in calls), calls
PY
printf '%s\n' 'Flatpak payload build mock: PASS'

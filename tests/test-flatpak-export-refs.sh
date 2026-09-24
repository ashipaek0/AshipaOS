#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
repo="$tmp/.ostree/repo"
mkdir -p "$tmp/.ostree"
app=app/com.github.iwalton3.jellyfin-mpv-shim/x86_64/stable
runtime=runtime/org.freedesktop.Platform/x86_64/25.08
extra=runtime/org.freedesktop.Platform.Locale/x86_64/25.08
appstream=appstream2/x86_64
ostree --repo="$repo" init --mode=archive
mkdir "$tmp/tree"
printf 'fixture\n' > "$tmp/tree/file"
app_commit=$(ostree --repo="$repo" commit --branch="$app" --tree="dir=$tmp/tree" --subject=app)
runtime_commit=$(ostree --repo="$repo" commit --branch="$runtime" --tree="dir=$tmp/tree" --subject=runtime)
ostree --repo="$repo" refs "$app_commit" --collections --create="org.flathub.Stable:$app"
ostree --repo="$repo" refs "$runtime_commit" --collections --create="org.flathub.Stable:$runtime"
ostree --repo="$repo" refs "$runtime_commit" --collections --create="org.flathub.Stable:$extra"
ostree --repo="$repo" refs "$runtime_commit" --collections --create="org.flathub.Stable:$appstream"
ostree --repo="$repo" refs "$app" --delete
ostree --repo="$repo" refs "$runtime" --delete
[[ -z $(ostree --repo="$repo" refs) ]] || { echo 'fixture has ordinary refs' >&2; exit 1; }
python3 "$root/scripts/lock-flatpak-export.py" "$repo" "$app" "$app_commit" \
  org.freedesktop.Platform/x86_64/25.08 "$runtime_commit" > "$tmp/lock.json"
python3 - "$tmp/lock.json" "$app" "$app_commit" "$runtime" "$runtime_commit" "$extra" "$appstream" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1]))
app, app_commit, runtime, runtime_commit, extra, appstream = sys.argv[2:]
assert {r['ref']: r['commit'] for r in lock['refs']} == {
    app: app_commit, runtime: runtime_commit, extra: runtime_commit}
assert {r['collection_id'] for r in lock['refs']} == {'org.flathub.Stable'}
assert lock['metadata_refs'] == [{'collection_id': 'org.flathub.Stable',
                                  'ref': appstream, 'commit': runtime_commit}]
PY
# Unknown refs remain rejected rather than silently treated as metadata.
unknown=metadata/unexpected/x86_64
ostree --repo="$repo" refs "$runtime_commit" --collections --create="org.flathub.Stable:$unknown"
if python3 "$root/scripts/lock-flatpak-export.py" "$repo" "$app" "$app_commit" \
    org.freedesktop.Platform/x86_64/25.08 "$runtime_commit" > "$tmp/bad.json"; then
  echo 'unknown export ref accepted' >&2; exit 1
fi
ostree --repo="$repo" refs --collections org.flathub.Stable --delete
ostree --repo="$repo" refs "$app_commit" --collections --create="org.flathub.Stable:$app"
ostree --repo="$repo" refs "$runtime_commit" --collections --create="org.flathub.Stable:$runtime"
ostree --repo="$repo" refs "$runtime_commit" --collections --create="org.flathub.Stable:$extra"
ostree --repo="$repo" refs "$runtime_commit" --collections --create="org.flathub.Stable:$appstream"
# A nonempty export lacking the installed runtime is not a valid lock.
ostree --repo="$repo" refs --collections org.flathub.Stable --delete
ostree --repo="$repo" refs "$app_commit" --collections --create="org.flathub.Stable:$app"
if python3 "$root/scripts/lock-flatpak-export.py" "$repo" "$app" "$app_commit" \
    org.freedesktop.Platform/x86_64/25.08 "$runtime_commit" > "$tmp/bad.json"; then
  echo 'missing runtime accepted' >&2; exit 1
fi
ostree --repo="$repo" refs --collections org.flathub.Stable --delete
if python3 "$root/scripts/lock-flatpak-export.py" "$repo" "$app" "$app_commit" \
    org.freedesktop.Platform/x86_64/25.08 "$runtime_commit" > "$tmp/bad.json"; then
  echo 'empty export accepted' >&2; exit 1
fi

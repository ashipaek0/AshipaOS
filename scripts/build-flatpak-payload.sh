#!/usr/bin/env bash
set -Eeuo pipefail
APP=com.github.iwalton3.jellyfin-mpv-shim
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=out/flatpak-repo; EVIDENCE_DIR=out/evidence; FLATPAK_HOME=$(mktemp -d)
trap 'rm -rf "$FLATPAK_HOME"' EXIT
mkdir -p "$REPO_DIR" "$EVIDENCE_DIR" "$FLATPAK_HOME"/{home,data,config,cache}
export HOME="$FLATPAK_HOME/home" XDG_DATA_HOME="$FLATPAK_HOME/data" XDG_CONFIG_HOME="$FLATPAK_HOME/config" XDG_CACHE_HOME="$FLATPAK_HOME/cache"
"$SCRIPT_DIR/capture-flathub-trust.sh" out
flatpak remote-add --user --if-not-exists --gpg-import=out/flathub.gpg --collection-id=org.flathub.Stable flathub https://dl.flathub.org/repo/
flatpak remote-modify --user --gpg-verify --collection-id=org.flathub.Stable flathub
flatpak install --user --noninteractive --or-update flathub "$APP"
REF=$(flatpak info --user --show-ref "$APP"); RUNTIME=$(flatpak info --user --show-runtime "$APP"); COMMIT=$(flatpak info --user --show-commit "$APP"); RUNTIME_COMMIT=$(flatpak info --user --show-commit "$RUNTIME")
[[ -n "$REF" && -n "$COMMIT" && -n "$RUNTIME" && -n "$RUNTIME_COMMIT" ]]
flatpak create-usb --help >/dev/null 2>&1 || { echo 'flatpak create-usb not available' >&2; exit 1; }
flatpak create-usb --user "$REPO_DIR" "$REF"
[[ -d "$REPO_DIR/.ostree/repo" ]] || { echo 'create-usb did not create the OSTree repository' >&2; exit 1; }
# create-usb writes mirror collection refs, not refs/heads; plain `ostree refs`
# omits them. Check that both the installed app and runtime were exported.
python3 "$SCRIPT_DIR/lock-flatpak-export.py" "$REPO_DIR/.ostree/repo" "$REF" "$COMMIT" "$RUNTIME" "$RUNTIME_COMMIT" \
  | tee out/flatpak-lock.json "$EVIDENCE_DIR/flatpak-lock.json" >/dev/null

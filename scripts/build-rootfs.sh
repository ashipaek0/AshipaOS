#!/usr/bin/env bash
set -Eeuo pipefail
out=${ROOTFS_OUT:-out/appliance-rootfs}; tmp=$(mktemp -d)
# A failed mmdebstrap (root mode) can leave /dev, /proc and /sys mounted in
# the rootfs. Unmount them before deleting, and never delete across a mount.
mounts_under() { findmnt -rn -o TARGET | awk -v p="$1/" 'index($0, p) == 1' | sort -r; }
unmount_under() {
  local m
  # Shared propagation can list one mount twice; the second umount then fails.
  mounts_under "$1" | while read -r m; do umount -l "$m" 2>/dev/null || true; done
  [[ -z "$(mounts_under "$1")" ]] || { echo "could not unmount everything under $1" >&2; return 1; }
}
cleanup() {
  set +e
  unmount_under "$tmp"
  rm -rf --one-file-system "$tmp"
}
trap cleanup EXIT
command -v mmdebstrap >/dev/null || { echo 'mmdebstrap is required in CI' >&2; exit 1; }
key=${ADMIN_SSH_PUBKEY:?ADMIN_SSH_PUBKEY secret is required}
"$(dirname "$0")/../provision/validate-admin-key.sh" "$key" || { echo 'invalid ADMIN_SSH_PUBKEY' >&2; exit 1; }
mirror=${DEBIAN_MIRROR:-http://snapshot.debian.org/archive/debian/20250901T000000Z/}
mkdir -p out
printf '%s\n' "debian_release=trixie" "debian_mirror=$mirror" > out/rootfs-build.lock
. scripts/flathub.env
[[ -s out/flathub.flatpakrepo && -s out/flathub.gpg && -s out/flathub-key-fingerprint.txt ]] || { echo 'captured Flathub trust material is required' >&2; exit 1; }
[[ "$(<out/flathub-key-fingerprint.txt)" == "$FLATHUB_KEY_FINGERPRINT" ]] || { echo 'Flathub signing key pin mismatch' >&2; exit 1; }
scripts/validate-flatpak-key.sh out/flathub.gpg "$FLATHUB_KEY_FINGERPRINT" "$FLATHUB_KEY_IDENTITY"
python3 - out/flathub.flatpakrepo "$FLATHUB_URL" <<'PY'
import configparser,sys
p=configparser.ConfigParser(interpolation=None); p.read(sys.argv[1]); s=p['Flatpak Repo']
if s.get('Url','').rstrip('/')+'/' != sys.argv[2]: raise SystemExit('captured Flathub URL mismatch')
PY
printf '%s\n' "flathub_url=$FLATHUB_URL" "flathub_collection_id=$FLATHUB_COLLECTION_ID" "flathub_key_fingerprint=$FLATHUB_KEY_FINGERPRINT" "flathub_key_sha256=$(sha256sum out/flathub.gpg | cut -d' ' -f1)" >> out/rootfs-build.lock
# grub-pc and grub-efi-amd64 conflict; the -bin packages carry both targets
# modules and grub2-common carries grub-install/grub-mkconfig for the image.
packages=systemd-sysv,systemd-resolved,linux-image-amd64,grub-pc-bin,grub-efi-amd64-bin,grub2-common,shim-signed,openssh-server,network-manager,greetd,labwc,flatpak,gnupg,pipewire,wireplumber,parted,e2fsprogs,cloud-init,ca-certificates,dbus-user-session,polkitd,libgtk-4-1,libadwaita-1-0,fonts-dejavu,seatd,util-linux,sudo,jq,python3-gi,gir1.2-gtk-4.0,lvm2,mdadm
# Ubuntu runners lack Debian archive keys. The pinned snapshot's InRelease is
# also signed by the bookworm archive key that Ubuntu's keyring package ships.
keyring=/usr/share/keyrings/debian-archive-keyring.gpg
[[ -s "$keyring" ]] || { echo 'debian-archive-keyring is required to verify the Debian snapshot' >&2; exit 1; }
mmdebstrap --variant=apt --keyring="$keyring" --architectures=amd64 --components=main --aptopt='Acquire::Check-Valid-Until "false"' --include="$packages" trixie "$tmp/rootfs" "$mirror"
root="$tmp/rootfs"
# mmdebstrap reports success even when a busy /sys fails to unmount; nothing
# from the host may stay mounted in the image tree.
unmount_under "$root"
install -d -m 0755 "$root/etc/ssh/sshd_config.d" "$root/etc/greetd" "$root/etc/labwc" "$root/etc/systemd/system" "$root/usr/local/bin" "$root/var/lib/ashipaos" "$root/home/admin/.ssh"
# Locked appliance accounts; admin access is exclusively through the supplied key.
chroot "$root" useradd --create-home --shell /bin/bash admin
chroot "$root" useradd --create-home --shell /usr/sbin/nologin kiosk
chroot "$root" passwd --lock admin
chroot "$root" passwd --lock kiosk
printf '%s\n' "$key" > "$root/home/admin/.ssh/authorized_keys"
chroot "$root" chown -R admin:admin /home/admin/.ssh; chmod 0700 "$root/home/admin/.ssh"; chmod 0600 "$root/home/admin/.ssh/authorized_keys"
cp provision/ssh-hardening.conf "$root/etc/ssh/sshd_config.d/ashipaos.conf"
cp provision/greetd-config.toml "$root/etc/greetd/config.toml"
cp provision/labwc-config "$root/etc/labwc/rc.xml"; cp provision/labwc-autostart "$root/etc/labwc/autostart"
cp provision/appliance-session provision/appliance-shell provision/appliance-settings provision/appliance-health-check provision/appliance-update "$root/usr/local/bin/"
chmod 0755 "$root/usr/local/bin/"*
cp provision/appliance-update.service "$root/etc/systemd/system/"
cp provision/appliance-update.timer "$root/etc/systemd/system/"
cat > "$root/etc/systemd/system/ashipaos-boot-ok.service" <<'UNIT'
[Unit]
Description=AshipaOS installed-system milestone
After=graphical.target greetd.service
Wants=graphical.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/ashipaos-readiness
RemainAfterExit=yes
[Install]
WantedBy=graphical.target
UNIT
cat > "$root/etc/fstab" <<'FSTAB'
# PARTUUID is filled by assemble-disk-image.sh after partitioning.
FSTAB
install -d -m 0755 "$root/usr/local/bin"
cat > "$root/usr/local/bin/ashipaos-readiness" <<'READY'
#!/bin/sh
set -eu
ok=0
for i in $(seq 1 30); do
  # flatpak ps only lists the caller's instances, so ask as the kiosk user.
  systemctl is-active --quiet greetd && labwc_check=$(systemctl is-active --quiet labwc 2>/dev/null || pgrep -x labwc 2>/dev/null) && runuser -u kiosk -- env XDG_RUNTIME_DIR="/run/user/$(id -u kiosk)" flatpak ps 2>/dev/null | grep -F 'com.github.iwalton3.jellyfin-mpv-shim' >/dev/null && ok=1 && break
  sleep 1
done
[ "$ok" = 1 ] || exit 1
printf 'ASHIPAOS_BOOT_OK\n' > /dev/ttyS0
READY
chmod 0755 "$root/usr/local/bin/ashipaos-readiness"
cat > "$root/etc/systemd/system/ashipaos-first-boot.service" <<'UNIT'
[Unit]
Description=Regenerate machine identity and SSH host keys
Before=sshd.service
ConditionPathExists=/var/lib/ashipaos/first-boot
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'rm -f /etc/machine-id; systemd-machine-id-setup; ssh-keygen -A; rm -f /var/lib/ashipaos/first-boot'
[Install]
WantedBy=multi-user.target
UNIT
touch "$root/var/lib/ashipaos/first-boot"
# Install the locked offline Flatpak graph into the system installation.
[[ -d out/flatpak-repo/.ostree/repo && -f out/flatpak-lock.json ]] || { echo 'offline Flatpak repo and lock are required' >&2; exit 1; }
refs_text=$(python3 scripts/flatpak-lock-refs.py out/flatpak-lock.json)
mapfile -t refs <<<"$refs_text"
cp -a out/flatpak-repo "$root/var/lib/ashipaos/flatpak-repo"
# Remote configuration and listing run on the host against the rootfs Flatpak
# directory (the rootfs has no ostree CLI); only the install runs in the chroot.
host_flatpak() { FLATPAK_SYSTEM_DIR="$root/var/lib/flatpak" "$@"; }
host_flatpak scripts/configure-flathub-remote.sh --system out/flathub.gpg
stage=/tmp/ashipaos-flatpak
install -d -m 0755 "$root$stage"
install -m 0755 scripts/install-flatpak-graph-offline.sh "$root$stage/"
install -m 0644 scripts/flathub.env "$root$stage/"
# Flatpak needs /proc (boot_id), /sys and /dev inside the chroot, and its
# bwrap-run triggers need the chroot root to be a private mount point. Mount
# them in a private, network-less namespace so nothing reaches the host (the
# runner's shared propagation would otherwise duplicate them) and they vanish
# when the install exits.
unshare --mount --net --propagation private sh -c '
  mount --bind "$1" "$1" &&
  mount -t proc proc "$1/proc" &&
  mount -t sysfs -o ro,nosuid,nodev,noexec sysfs "$1/sys" &&
  mount --bind /dev "$1/dev" &&
  root=$1 && shift && exec chroot "$root" "$@"
' _ "$root" "$stage/install-flatpak-graph-offline.sh" --system /var/lib/ashipaos/flatpak-repo/.ostree/repo "${refs[@]}"
rm -rf "$root$stage"
host_flatpak scripts/list-installed-flatpaks.sh --system > "$tmp/installed-flatpak.tsv"
python3 scripts/verify-flatpak-lock.py out/flatpak-lock.json "$tmp/installed-flatpak.tsv"
# Re-check the remote after the install so the image ships the pinned configuration.
host_flatpak scripts/configure-flathub-remote.sh --system out/flathub.gpg
chroot "$root" usermod -aG video,render,audio kiosk
host_flatpak flatpak --system override --socket=wayland --socket=x11 --device=dri --share=ipc "$APP_ID"
cp provision/flatpak-permissions "$root/etc/flatpak-permissions"
cp out/flatpak-lock.json "$root/var/lib/ashipaos/flatpak-lock.json"
# Seal only after identity material and all operational configuration are ready.
rm -f "$root/etc/machine-id" "$root/etc/ssh/ssh_host_"*
rm -f "$root/etc/resolv.conf"; ln -s /run/systemd/resolve/stub-resolv.conf "$root/etc/resolv.conf"
chroot "$root" systemctl enable ssh.service greetd NetworkManager appliance-update.timer ashipaos-first-boot.service ashipaos-boot-ok.service
chroot "$root" systemctl enable systemd-resolved
install -d -m 0755 "$root/etc/NetworkManager/conf.d"
printf '[main]\ndns=systemd-resolved\n' > "$root/etc/NetworkManager/conf.d/20-resolved.conf"
chroot "$root" systemctl set-default graphical.target
rm -rf "$out"; mv "$root" "$out"; touch "$out/.sealed"

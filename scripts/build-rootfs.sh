#!/usr/bin/env bash
set -Eeuo pipefail
out=${ROOTFS_OUT:-out/appliance-rootfs}; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
command -v mmdebstrap >/dev/null || { echo 'mmdebstrap is required in CI' >&2; exit 1; }
key=${ADMIN_SSH_PUBKEY:?ADMIN_SSH_PUBKEY secret is required}
"$(dirname "$0")/../provision/validate-admin-key.sh" "$key" || { echo 'invalid ADMIN_SSH_PUBKEY' >&2; exit 1; }
mirror=${DEBIAN_MIRROR:-http://snapshot.debian.org/archive/debian/20250901T000000Z/}
mkdir -p out
printf '%s\n' "debian_release=trixie" "debian_mirror=$mirror" > out/rootfs-build.lock
[[ -s out/flathub.flatpakrepo && -s out/flathub.gpg && -s out/flathub-key-fingerprint.txt ]] || { echo 'captured Flathub trust material is required' >&2; exit 1; }
fingerprint=$(<out/flathub-key-fingerprint.txt)
[[ "$fingerprint" == 6E5C05D979C76DAF93C081354184DD4D907A7CAE ]] || { echo 'Flathub signing key pin mismatch' >&2; exit 1; }
scripts/validate-flatpak-key.sh out/flathub.gpg "$fingerprint" 'Flathub Repo Signing Key <flathub@flathub.org>'
python3 - out/flathub.flatpakrepo <<'PY'
import configparser,sys
p=configparser.ConfigParser(interpolation=None); p.read(sys.argv[1]); s=p['Flatpak Repo']
if s.get('Url','').rstrip('/')+'/' != 'https://dl.flathub.org/repo/': raise SystemExit('captured Flathub URL mismatch')
PY
printf '%s\n' 'flathub_url=https://dl.flathub.org/repo/' 'flathub_collection_id=org.flathub.Stable' "flathub_key_fingerprint=$fingerprint" "flathub_key_sha256=$(sha256sum out/flathub.gpg | cut -d' ' -f1)" >> out/rootfs-build.lock
packages=systemd-sysv,systemd-resolved,linux-image-amd64,grub-pc,grub-efi-amd64,shim-signed,openssh-server,network-manager,greetd,labwc,flatpak,gnupg,pipewire,wireplumber,parted,e2fsprogs,cloud-init,ca-certificates,dbus-user-session,policykit-1,libgtk-3-0,libgtk-4-1,libadwaita-1-0,fonts-dejavu,seatd,util-linux,sudo,jq,python3-gi,gir1.2-gtk-4.0,lvm2,mdadm
mmdebstrap --variant=apt --architectures=amd64 --components=main --aptopt='Acquire::Check-Valid-Until "false"' --include="$packages" trixie "$tmp/rootfs" "$mirror"
root="$tmp/rootfs"
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
  systemctl is-active --quiet greetd && labwc_check=$(systemctl is-active --quiet labwc 2>/dev/null || pgrep -x labwc 2>/dev/null) && flatpak ps 2>/dev/null | grep -F 'com.github.iwalton3.jellyfin-mpv-shim' >/dev/null && ok=1 && break
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
if [[ -d out/flatpak-repo/.ostree/repo && -f out/flatpak-lock.json ]]; then
  mapfile -t lock_rows < <(python3 - <<'PY'
import json
x=json.load(open('out/flatpak-lock.json'))
assert x.get('collection_id') == 'org.flathub.Stable' and x.get('refs')
for r in x['refs']: print(r['ref']+'\t'+r['commit'])
PY
)
  ((${#lock_rows[@]} > 0)) || { echo 'flatpak lock graph is incomplete' >&2; exit 1; }
  app_ref=$(python3 -c 'import json; print(json.load(open("out/flatpak-lock.json"))["app"])')
  cp -a out/flatpak-repo "$root/var/lib/ashipaos/flatpak-repo"
  install -D -m 0755 scripts/configure-flatpak-offline-remote.sh "$root/usr/local/lib/ashipaos/configure-flatpak-offline-remote.sh"
  install -m 0755 scripts/validate-flatpak-key.sh "$root/usr/local/lib/ashipaos/validate-flatpak-key.sh"
  install -m 0644 out/flathub.gpg "$root/tmp/ashipaos-flathub.gpg"

  chroot "$root" flatpak --system remote-add --if-not-exists --gpg-import=/tmp/ashipaos-flathub.gpg --collection-id=org.flathub.Stable flathub https://dl.flathub.org/repo/
  chroot "$root" flatpak --system remote-modify --gpg-verify --collection-id=org.flathub.Stable flathub
  refs=(); for row in "${lock_rows[@]}"; do refs+=("${row%%$'\t'*}"); done
  unshare -n chroot "$root" flatpak --system install --noninteractive --sideload-repo=/var/lib/ashipaos/flatpak-repo/.ostree/repo flathub "${refs[@]}"
  for row in "${lock_rows[@]}"; do ref=${row%%$'\t'*}; expected=${row#*$'\t'}; actual=$(chroot "$root" flatpak --system info --show-commit "$ref"); [[ "$actual" == "$expected" ]] || { echo "Flatpak commit mismatch for $ref" >&2; exit 1; }; done
  chroot "$root" flatpak --system list --columns=ref,commit > "$tmp/installed-flatpak.tsv"
  python3 scripts/verify-flatpak-lock.py out/flatpak-lock.json "$tmp/installed-flatpak.tsv"
  chroot "$root" /usr/local/lib/ashipaos/configure-flatpak-offline-remote.sh --system restore /var/lib/flatpak/repo /tmp/ashipaos-flathub.gpg "$fingerprint"
  rm -f "$root/tmp/ashipaos-flathub.gpg"
  chroot "$root" usermod -aG video,render,audio kiosk
  chroot "$root" flatpak --system override --socket=wayland --socket=x11 --device=dri --share=ipc "$app_ref"
  cp provision/flatpak-permissions "$root/etc/flatpak-permissions"
  cp out/flatpak-lock.json "$root/var/lib/ashipaos/flatpak-lock.json"
else
  echo 'offline Flatpak repo and lock are required' >&2; exit 1
fi
# Seal only after identity material and all operational configuration are ready.
rm -f "$root/etc/machine-id" "$root/etc/ssh/ssh_host_"*
rm -f "$root/etc/resolv.conf"; ln -s /run/systemd/resolve/stub-resolv.conf "$root/etc/resolv.conf"
chroot "$root" systemctl enable ssh.service greetd NetworkManager appliance-update.timer ashipaos-first-boot.service ashipaos-boot-ok.service
chroot "$root" systemctl enable systemd-resolved
install -d -m 0755 "$root/etc/NetworkManager/conf.d"
printf '[main]\ndns=systemd-resolved\n' > "$root/etc/NetworkManager/conf.d/20-resolved.conf"
chroot "$root" systemctl set-default graphical.target
rm -rf "$out"; mv "$root" "$out"; touch "$out/.sealed"

#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:?mode}; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
name=sda; [[ "$mode" == nvme ]] && name=nvme0n1
[[ "$mode" == mmc ]] && name=mmcblk0
mkdir -p "$tmp/dev" "$tmp/sys/block/$name" "$tmp/bin" "$tmp/mount-root/var/lib/ashipaos"
printf '22000000000\n0\n0\n-\n' > "$tmp/sys/block/$name/attrs"
: > "$tmp/dev/$name"
for n in 1 2 3; do
  case "$name" in nvme*|mmc*) part="${name}p$n";; *) part="${name}$n";; esac
  mkdir -p "$tmp/sys/block/$name/$part"
  : > "$tmp/dev/$part"
done
printf 'installed\n' > "$tmp/mount-root/var/lib/ashipaos/install-complete"
printf 'Filename\tType\tSize\n' > "$tmp/swaps"
cat > "$tmp/bin/lsblk" <<'SH'
#!/usr/bin/env bash
name=${TEST_NAME}; root=${DEV_ROOT}
case " $* " in
 *' -nro PARTTYPE '*)
   if [[ "${TEST_PARTTYPE:-}" == wrong ]]; then echo 00000000-0000-0000-0000-000000000000
   else case "${*: -1}" in *1) echo 21686148-6449-6e6f-744e-656564454649;; *2) echo c12a7328-f81f-11d2-ba4b-00a0c93ec93b;; *3) echo 0fc63daf-8483-4772-8e79-3d69d8477de4;; esac; fi;;
 *' -nrpo NAME,TYPE '*) echo "$root/$name disk"; for n in 1 2 3; do case "$name" in nvme*|mmc*) echo "$root/${name}p$n part";; *) echo "$root/${name}$n part";; esac; done; [[ "${TEST_EXTRA:-}" != 1 ]] || echo "$root/${name}4 part";;
 *' -nr -o NAME,TYPE '*) echo "$name disk"; for n in 1 2 3; do case "$name" in nvme*|mmc*) echo "${name}p$n part";; *) echo "${name}$n part";; esac; done;;
 *' -ndo PKNAME '*) echo "$name";;
esac
SH
cat > "$tmp/bin/blkid" <<'SH'
#!/usr/bin/env bash
node=${*: -1}; name=${node##*/}
case " $* " in
 *' -s LABEL '*) case "$name" in *2) echo ASHIPAOS;; *3) echo ASHIPAOS_ROOT;; esac;;
 *' -p -o export '*)
   case "${TEST_SIGNATURE:-}" in
     unexpected) [[ "$name" == *2 ]] && { echo TYPE=ntfs; exit 0; };;
     lvm-signature) [[ "$name" == *2 ]] && { echo TYPE=LVM2_member; exit 0; };;
     raid-signature) [[ "$name" == *2 ]] && { echo TYPE=linux_raid_member; exit 0; };;
     extra-signature) [[ "$name" == *2 ]] && { printf 'TYPE=vfat\nLABEL=ASHIPAOS\nEXTRA=foreign\n'; exit 0; };;
   esac
   if [[ "$name" == "$TEST_NAME" ]]; then echo PTTYPE=gpt
   elif [[ "$name" == *2 ]]; then printf 'TYPE=vfat\nLABEL=ASHIPAOS\n'
   elif [[ "$name" == *3 ]]; then printf 'TYPE=ext4\nLABEL=ASHIPAOS_ROOT\n'; fi;;
esac
SH
cat > "$tmp/bin/mount" <<'SH'
#!/usr/bin/env bash
[[ "$1" == -o && "$2" == ro,noload,nosuid,nodev,noexec ]] || exit 1
mkdir -p "$4/var/lib/ashipaos"; cp "$TEST_MARKER" "$4/var/lib/ashipaos/install-complete"
SH
cat > "$tmp/bin/umount" <<'SH'
#!/usr/bin/env bash
rm -rf "$1/var"
SH
cat > "$tmp/bin/findmnt" <<'SH'
#!/usr/bin/env bash
[[ "${TEST_FINDMNT_FAIL:-0}" == 1 ]] && exit 1
[[ -n "${TEST_MOUNT:-}" ]] && echo "$TEST_MOUNT" || true
SH
for tool in pvs dmsetup mdadm; do
cat > "$tmp/bin/$tool" <<'SH'
#!/usr/bin/env bash
[[ "${TEST_REJECT_TOOL:-}" == "${0##*/}" && "${*: -1}" == *2 ]] || exit 1
[[ "${0##*/}" != pvs ]] || echo /dev/pv
SH
done
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" SYSFS_ROOT="$tmp/sys" DEV_ROOT="$tmp/dev" MARKER_TMP_ROOT="$tmp" SWAPS_FILE="$tmp/swaps" TEST_NAME="$name" TEST_MARKER="$tmp/mount-root/var/lib/ashipaos/install-complete" SELECTOR_PRODUCTION_PROBES=1
run() { if [[ "${DEBUG:-}" == 1 ]]; then bash -x "$root/installer/select-target.sh" --fixture-root ashipaos.force=1 "ashipaos.install_target=/dev/$name"; else "$root/installer/select-target.sh" --fixture-root ashipaos.force=1 "ashipaos.install_target=/dev/$name"; fi; }
case "$mode" in
  sata|nvme|mmc) [[ $(run) == "$tmp/dev/$name" ]]; unset TEST_MOUNT TEST_SIGNATURE TEST_REJECT_TOOL;;
  mount) TEST_MOUNT="$tmp/dev/${name}2"; export TEST_MOUNT; ! run;;
  mount-subpath|mount-subpath-force) TEST_MOUNT="$tmp/dev/${name}3[/subdir]"; export TEST_MOUNT; if [[ "$mode" == mount-subpath ]]; then ! "$root/installer/select-target.sh" --fixture-root "ashipaos.install_target=/dev/$name"; else ! run; fi;;
  findmnt-fail|findmnt-fail-force) TEST_FINDMNT_FAIL=1; export TEST_FINDMNT_FAIL; if [[ "$mode" == findmnt-fail ]]; then ! "$root/installer/select-target.sh" --fixture-root "ashipaos.install_target=/dev/$name"; else ! run; fi;;
  swap) printf '%s partition 1 0 -2\n' "$tmp/dev/${name}2" >> "$tmp/swaps"; ! run;;
  holder) mkdir -p "$tmp/sys/block/$name/${name}2/holders"; : > "$tmp/sys/block/$name/${name}2/holders/dm-0"; ! run;;
  unexpected|lvm-signature|raid-signature|extra-signature) TEST_SIGNATURE="$mode"; export TEST_SIGNATURE; ! run;;
  wrong-parttype) TEST_PARTTYPE=wrong; export TEST_PARTTYPE; ! run;;
  pvs|mdadm|dmsetup) TEST_REJECT_TOOL="$mode"; export TEST_REJECT_TOOL; ! run;;
  extra) mkdir -p "$tmp/sys/block/$name/${name}4"; : > "$tmp/dev/${name}4"; export TEST_EXTRA=1; ! run;;
  normal) ! "$root/installer/select-target.sh" --fixture-root "ashipaos.install_target=/dev/$name";;
  *) exit 2;;
esac

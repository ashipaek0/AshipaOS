#!/usr/bin/env bash
set -Eeuo pipefail
# Exercise the selector's production probes (lsblk, blkid, mount, mdadm, ...)
# through mocks: a completed install is always refused, a blank disk must pass
# every whole-disk safety check.
root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:?mode}; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
name=sda; [[ "$mode" == installed-nvme ]] && name=nvme0n1
[[ "$mode" == installed-mmc ]] && name=mmcblk0
layout=blank; [[ "$mode" == installed* ]] && layout=installed
mkdir -p "$tmp/dev" "$tmp/sys/block/$name" "$tmp/bin" "$tmp/mount-root/var/lib/ashipaos"
printf '22000000000\n0\n0\n-\n' > "$tmp/sys/block/$name/attrs"
: > "$tmp/dev/$name"
if [[ "$layout" == installed ]]; then
  for n in 1 2 3; do
    case "$name" in nvme*|mmc*) part="${name}p$n";; *) part="${name}$n";; esac
    mkdir -p "$tmp/sys/block/$name/$part"
    : > "$tmp/dev/$part"
  done
fi
printf 'installed\n' > "$tmp/mount-root/var/lib/ashipaos/install-complete"
printf 'Filename\tType\tSize\n' > "$tmp/swaps"
cat > "$tmp/bin/lsblk" <<'SH'
#!/usr/bin/env bash
name=${TEST_NAME}; root=${DEV_ROOT}
parts() { [[ "$TEST_LAYOUT" == installed ]] || return 0; for n in 1 2 3; do case "$name" in nvme*|mmc*) echo "$1${name}p$n part";; *) echo "$1${name}$n part";; esac; done; }
case " $* " in
 *' -nrpo NAME,TYPE '*) echo "$root/$name disk"; parts "$root/";;
 *' -nr -o NAME,TYPE '*) echo "$name disk"; parts '';;
 *' -ndo PKNAME '*) echo "$name";;
esac
SH
cat > "$tmp/bin/blkid" <<'SH'
#!/usr/bin/env bash
node=${*: -1}; name=${node##*/}
case " $* " in
 *' -s LABEL '*) case "$name" in *2) echo ASHIPAOS;; *3) echo ASHIPAOS_ROOT;; esac;;
 *' -p -o export '*)
   # A blank disk has no signature; a stale one must be refused.
   [[ "${TEST_SIGNATURE:-}" == 1 && "$name" == "$TEST_NAME" ]] && printf 'DEVNAME=%s\nPTTYPE=gpt\n' "$node"
   exit 0;;
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
for tool in pvs dmsetup; do
cat > "$tmp/bin/$tool" <<'SH'
#!/usr/bin/env bash
[[ "${TEST_REJECT_TOOL:-}" == "${0##*/}" ]] || exit 1
[[ "${0##*/}" != pvs ]] || echo /dev/pv
SH
done
# Like real mdadm: --examine succeeds on any partition table (protective MBR);
# only an md member exports MD_UUID.
cat > "$tmp/bin/mdadm" <<'SH'
#!/usr/bin/env bash
[[ "$*" == *--export* ]] || { echo 'MBR Magic : aa55'; exit 0; }
[[ "${TEST_REJECT_TOOL:-}" == mdadm ]] && echo 'MD_UUID=00000000:00000000:00000000:00000000'
exit 0
SH
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" SYSFS_ROOT="$tmp/sys" DEV_ROOT="$tmp/dev" MARKER_TMP_ROOT="$tmp" SWAPS_FILE="$tmp/swaps" TEST_NAME="$name" TEST_LAYOUT="$layout" TEST_MARKER="$tmp/mount-root/var/lib/ashipaos/install-complete" SELECTOR_PRODUCTION_PROBES=1
run() { "$root/installer/select-target.sh" --fixture-root "ashipaos.install_target=/dev/$name" "$@"; }
refused_marker() { ! run "$@" 2> "$tmp/err"; grep -qx ASHIPAOS_INSTALL_REFUSED_MARKER "$tmp/err"; }
case "$mode" in
  installed-sata|installed-nvme|installed-mmc) refused_marker;;
  # The removed force option must not come back through the kernel command line.
  installed-force-arg) refused_marker ashipaos.force=1;;
  blank) [[ $(run) == "$tmp/dev/$name" ]];;
  mount) TEST_MOUNT="$tmp/dev/$name"; export TEST_MOUNT; ! run;;
  mount-subpath) TEST_MOUNT="$tmp/dev/$name[/subdir]"; export TEST_MOUNT; ! run;;
  findmnt-fail) TEST_FINDMNT_FAIL=1; export TEST_FINDMNT_FAIL; ! run;;
  swap) printf '%s partition 1 0 -2\n' "$tmp/dev/$name" >> "$tmp/swaps"; ! run;;
  holder) mkdir -p "$tmp/sys/block/$name/holders"; : > "$tmp/sys/block/$name/holders/dm-0"; ! run;;
  signature) TEST_SIGNATURE=1; export TEST_SIGNATURE; ! run;;
  pvs|mdadm|dmsetup) TEST_REJECT_TOOL="$mode"; export TEST_REJECT_TOOL; ! run;;
  *) exit 2;;
esac

#!/usr/bin/env bash
set -Eeuo pipefail
firmware=${1:?bios or uefi}; iso=${2:?ISO path}; disk=${DISK_IMAGE:-out/vm-disk.img}; timeout_s=${VM_TIMEOUT_SECONDS:-360}
source "$(dirname "$0")/../installer/config.sh"
[[ -s "$iso" && -f "$disk" ]] || exit 1
(( $(stat -c %s "$disk") >= MIN_INSTALL_DISK_BYTES )) || { echo 'VM disk is below canonical appliance target' >&2; exit 1; }
mkdir -p out/evidence
[[ "$firmware" == bios || "$firmware" == uefi ]] || exit 2
if [[ "$firmware" == uefi ]]; then
  # Ubuntu 24.04's ovmf ships only the 4M builds.
  OVMF_CODE=${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
  OVMF_VARS=${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
  [[ -s "$OVMF_CODE" && -s "$OVMF_VARS" ]] || { echo "OVMF firmware missing: $OVMF_CODE / $OVMF_VARS" >&2; exit 1; }
  export OVMF_CODE OVMF_VARS
fi
qemu_version=$(qemu-system-x86_64 --version | head -n1)
declare -a vars_files=()
# The guest's tty turns "\n" into "\r\n" on the serial line, so compare whole
# lines with CRs stripped. grep without -q reads all input: no SIGPIPE under
# pipefail.
has_line() { tr -d '\r' < "$1" | grep -Fx -- "$2" >/dev/null; }
# Diagnostics artifacts are not always reachable; put the serial tail in the job log.
show_tail() {
  echo "--- last serial lines of $1 ---" >&2
  tr -d '\r' < "$1" | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g' | grep -av '^[[:space:]]*$' | tail -n 60 >&2 || true
}
stage_args() {
  local stage=$1 mode=$2
  # -nographic would also claim stdio for the monitor and clash with -serial.
  args=(-display none -serial stdio -m 2048 -nic none -no-reboot)
  # Stages write and hash a 20 GiB image; software emulation cannot do that
  # inside the stage timeout, so use KVM whenever the runner exposes it.
  if [[ -r /dev/kvm && -w /dev/kvm ]]; then args+=(-accel kvm -cpu host); fi
  if [[ "$firmware" == uefi ]]; then
    local vars="out/OVMF_VARS-${firmware}-${stage}.fd"
    cp "$OVMF_VARS" "$vars"
    vars_files+=("$vars")
    args+=(-drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" -drive "if=pflash,format=raw,file=$vars")
  fi
  if [[ "$mode" == iso ]]; then args+=(-drive "file=$iso,media=cdrom,readonly=on" -boot d); fi
  # Keep the zero-filled image sparse on the runner as the installer streams it.
  args+=(-drive "file=$disk,format=raw,if=virtio,discard=unmap,detect-zeroes=unmap")
}
run_stage() {
  local stage=$1 mode=$2 token=$3 log="out/evidence/vm-${firmware}-${1}.log" status=0
  stage_args "$stage" "$mode"
  timeout --foreground "$timeout_s" qemu-system-x86_64 "${args[@]}" > "$log" 2>&1 || status=$?
  (( status == 0 || status == 124 )) || { echo "VM $stage failed with $status" >&2; show_tail "$log"; return 1; }
  has_line "$log" "$token" || { echo "VM $stage milestone $token missing" >&2; show_tail "$log"; return 1; }
}
run_stage install iso ASHIPAOS_INSTALL_OK
run_stage installed disk ASHIPAOS_BOOT_OK
baseline=$(sha256sum "$disk" | awk '{print $1}')
run_stage guard iso ASHIPAOS_INSTALL_REFUSED_MARKER
[[ "$baseline" == "$(sha256sum "$disk" | awk '{print $1}')" ]] || { echo 'guard stage changed target disk' >&2; exit 1; }
python3 - "$firmware" "$iso" "$disk" "$baseline" "$qemu_version" "${vars_files[@]}" <<'PY'
import hashlib,json,os,platform,subprocess,sys,time
firmware,iso,disk,guard_hash,qemu,*vars_files=sys.argv[1:]
def digest(path):
    with open(path,'rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()
ci=os.environ.get('CI') == 'true' or os.environ.get('GITHUB_ACTIONS') == 'true'
commit=os.environ.get('GITHUB_SHA'); run_id=os.environ.get('GITHUB_RUN_ID'); job=os.environ.get('GITHUB_JOB')
if ci and not all((commit,run_id,job)): raise SystemExit('CI evidence identity is incomplete')
firmware_path=os.environ.get('OVMF_CODE') if firmware=='uefi' else next((p for p in ('/usr/share/seabios/bios.bin','/usr/share/qemu/bios.bin') if os.path.isfile(p)), None)
firmware_evidence={'path':firmware_path,'sha256':digest(firmware_path) if firmware_path and os.path.isfile(firmware_path) else None}
json.dump({'commit':commit or 'local','run_id':run_id or 'local','job':job or 'local','timestamp':int(time.time()),'iso_sha256':digest(iso),'disk_sha256':digest(disk),'result':'PASS','firmware':firmware_evidence,'ovmf_vars':{p:digest(p) for p in vars_files},'qemu_version':qemu,'guard_sha256':guard_hash,'runner_os':platform.platform(),'arch':platform.machine(),'stages':['install','installed','guard']},open(f'out/evidence/vm-{firmware}-manifest.json','w'),sort_keys=True)
PY
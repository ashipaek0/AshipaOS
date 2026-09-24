#!/usr/bin/env bash
set -Eeuo pipefail
firmware=${1:?bios or uefi}; iso=${2:?ISO path}; disk=${DISK_IMAGE:-out/vm-disk.img}; timeout_s=${VM_TIMEOUT_SECONDS:-360}
source "$(dirname "$0")/../installer/config.sh"
[[ -s "$iso" && -f "$disk" ]] || exit 1
(( $(stat -c %s "$disk") >= MIN_INSTALL_DISK_BYTES )) || { echo 'VM disk is below canonical appliance target' >&2; exit 1; }
mkdir -p out/evidence
[[ "$firmware" == bios || "$firmware" == uefi ]] || exit 2
if [[ "$firmware" == uefi ]]; then
  OVMF_CODE=${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE.fd}
  OVMF_VARS=${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS.fd}
  [[ -s "$OVMF_CODE" && -s "$OVMF_VARS" ]] || exit 1
  export OVMF_CODE OVMF_VARS
fi
qemu_version=$(qemu-system-x86_64 --version | head -n1)
declare -a vars_files=()
stage_args() {
  local stage=$1 mode=$2
  args=(-nographic -serial stdio -m 2048 -nic none -no-reboot)
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
  if [[ "$stage" == force ]]; then
    local socket="out/evidence/vm-${firmware}-force.monitor" pid
    rm -f "$socket"
    timeout --foreground "$timeout_s" qemu-system-x86_64 "${args[@]}" -monitor "unix:$socket,server,nowait" > "$log" 2>&1 & pid=$!
    # Select the actual second GRUB entry through QEMU's monitor. Refuse to
    # claim force coverage if the menu was never observed or no monitor exists.
    if ! python3 - "$socket" "$log" "$pid" <<'PY'
import os,socket,sys,time
path,log,pid=sys.argv[1:]
deadline=time.monotonic()+90
while time.monotonic()<deadline:
    try: text=open(log,errors='replace').read()
    except FileNotFoundError: text=''
    if 'Force reinstall AshipaOS offline' in text and os.path.exists(path):
        with socket.socket(socket.AF_UNIX) as client:
            client.connect(path)
            client.sendall(b'sendkey down\nsendkey ret\n')
        break
    try: os.kill(int(pid),0)
    except ProcessLookupError: raise SystemExit('VM exited before GRUB force menu')
    time.sleep(.2)
else: raise SystemExit('GRUB force menu/monitor not observed')
PY
    then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; return 1; fi
    wait "$pid" || status=$?
  else
    timeout --foreground "$timeout_s" qemu-system-x86_64 "${args[@]}" > "$log" 2>&1 || status=$?
  fi
  (( status == 0 || status == 124 )) || { echo "VM $stage failed with $status" >&2; return 1; }
  if [[ "$stage" == force ]]; then grep -Fxq ASHIPAOS_FORCE_REINSTALL_BEGIN "$log" || { echo 'force selector/write path not reached' >&2; return 1; }; fi
  grep -Fxq "$token" "$log" || { echo "VM $stage milestone $token missing" >&2; return 1; }
}
run_stage install iso ASHIPAOS_INSTALL_OK
run_stage installed disk ASHIPAOS_BOOT_OK
baseline=$(sha256sum "$disk" | awk '{print $1}')
run_stage guard iso ASHIPAOS_INSTALL_REFUSED_MARKER
[[ "$baseline" == "$(sha256sum "$disk" | awk '{print $1}')" ]] || { echo 'guard stage changed target disk' >&2; exit 1; }
run_stage force iso ASHIPAOS_INSTALL_OK
run_stage force-installed disk ASHIPAOS_BOOT_OK
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
json.dump({'commit':commit or 'local','run_id':run_id or 'local','job':job or 'local','timestamp':int(time.time()),'iso_sha256':digest(iso),'disk_sha256':digest(disk),'result':'PASS','firmware':firmware_evidence,'ovmf_vars':{p:digest(p) for p in vars_files},'qemu_version':qemu,'guard_sha256':guard_hash,'runner_os':platform.platform(),'arch':platform.machine(),'stages':['install','installed','guard','force','force-installed']},open(f'out/evidence/vm-{firmware}-manifest.json','w'),sort_keys=True)
PY
#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd); mode=${1:?mode}; bad_guard=0
if [[ "$mode" == bad-guard ]]; then mode=bios; bad_guard=1; fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/work/out"; printf iso > "$tmp/work/out/installer.iso"; printf disk > "$tmp/work/out/vm-disk.img"; printf code > "$tmp/work/code.fd"; printf vars > "$tmp/work/vars.fd"
cat > "$tmp/bin/stat" <<'SH'
#!/bin/bash
[[ "$2" == %s && "$3" == *vm-disk.img ]] && { echo 22000000000; exit; }
/usr/bin/stat "$@"
SH
cat > "$tmp/bin/sha256sum" <<'SH'
#!/bin/bash
[[ "$1" == *vm-disk.img ]] && { echo "constant  $1"; exit; }
/usr/bin/sha256sum "$@"
SH
cat > "$tmp/bin/qemu-system-x86_64" <<'PY'
#!/usr/bin/env python3
import os,socket,sys,time
args=sys.argv[1:]
if '--version' in args:
    print('QEMU emulator version mock'); sys.exit()
# A real guest tty emits CRLF on the serial line.
sys.stdout.reconfigure(newline='\r\n')
record=os.environ['VM_MOCK_RECORD']
with open(record,'a') as out: out.write(' '.join(args)+'\n')
index=len(open(record).readlines())
if '-monitor' in args:
    monitor=args[args.index('-monitor')+1].split(',')[0][5:]
    listener=socket.socket(socket.AF_UNIX)
    listener.bind(monitor);listener.listen(1)
    print('Force reinstall AshipaOS offline',flush=True)
    listener.settimeout(5)
    connection,_=listener.accept()
    command=connection.recv(1024)
    if b'sendkey down' not in command or b'sendkey ret' not in command: sys.exit(1)
    print('ASHIPAOS_FORCE_REINSTALL_BEGIN',flush=True)
    print('ASHIPAOS_INSTALL_OK',flush=True)
    connection.close();listener.close()
else:
    guard='noise ASHIPAOS_INSTALL_REFUSED_MARKER noise' if os.environ.get('VM_MOCK_BAD_GUARD')=='1' else 'ASHIPAOS_INSTALL_REFUSED_MARKER'
    print(['ASHIPAOS_INSTALL_OK','ASHIPAOS_BOOT_OK',guard,'', 'ASHIPAOS_BOOT_OK'][index-1],flush=True)
PY
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" VM_MOCK_RECORD="$tmp/record" OVMF_CODE="$tmp/work/code.fd" OVMF_VARS="$tmp/work/vars.fd" VM_MOCK_BAD_GUARD="$bad_guard"
if (( bad_guard )); then
  ! (cd "$tmp/work" && VM_TIMEOUT_SECONDS=7 "$root/scripts/vm-test.sh" "$mode" out/installer.iso)
  [[ ! -e "$tmp/work/out/evidence/vm-bios-manifest.json" ]]
  exit 0
fi
(cd "$tmp/work" && VM_TIMEOUT_SECONDS=7 "$root/scripts/vm-test.sh" "$mode" out/installer.iso)
python3 - "$tmp/work/out/evidence/vm-$mode-manifest.json" "$tmp/record" "$mode" <<'PY'
import json,sys
manifest=json.load(open(sys.argv[1])); stages=open(sys.argv[2]).readlines()
assert manifest['result']=='PASS' and len(stages)==5
assert all('-nic none' in s for s in stages)
assert 'media=cdrom' not in stages[1] and 'media=cdrom' not in stages[4]
assert 'media=cdrom' in stages[0] and 'media=cdrom' in stages[2] and 'media=cdrom' in stages[3]
assert manifest['stages']==['install','installed','guard','force','force-installed']
assert manifest['qemu_version']=='QEMU emulator version mock'
if sys.argv[3]=='uefi':
    assert len(manifest['ovmf_vars'])==5 and manifest['firmware']['sha256']
    assert len(set(map(lambda s:s.split('format=raw,file=')[1].split()[0],stages)))==5
PY

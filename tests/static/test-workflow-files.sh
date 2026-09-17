#!/usr/bin/env bash
# Layer 0 STATIC: GitHub workflow files must be well-formed YAML.
# Uses PyYAML if present; otherwise falls back to a minimal sanity check.
# Never fails for missing optional dependencies.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PYEOF'
import sys, os, glob

root = sys.argv[1]
files = sorted(glob.glob(os.path.join(root, ".github/workflows/*.yml")))
assert files, "no workflow files found"

try:
    import yaml  # type: ignore
    have_yaml = True
except ImportError:
    have_yaml = False

for p in files:
    with open(p) as f:
        text = f.read()
    assert text.strip(), "empty: %s" % p
    if have_yaml:
        d = yaml.safe_load(text)
        assert isinstance(d, dict), "not a mapping: %s" % p
        assert "jobs" in d, "missing jobs: %s" % p
        print("yaml-ok: %s" % os.path.relpath(p, root))
    else:
        assert "jobs:" in text, "missing jobs: %s" % p
        print("sanity-ok (pyyaml unavailable, SKIP parse): %s" % os.path.relpath(p, root))

    if os.path.basename(p) == "build-images.yml":
        assert text.count("linux-image-generic") >= 2, "each image job must provide a supermin kernel"
        assert text.count("libguestfs-test-tool") >= 2, "each image job must preflight libguestfs"
        x86 = text[text.index("  build-x86_64:"):text.index("  build-a95x-f3-air:")]
        arm = text[text.index("  build-a95x-f3-air:"):text.index("  create-release:")]
        assert "qemu-system-x86" in x86 and "ovmf" in x86, "x86_64 job must install UEFI QEMU dependencies"
        assert "util-linux" in x86, "x86_64 job must install stdbuf provider (util-linux)"
        assert "tests/vm/boot-x86_64.sh" in x86, "x86_64 VM gate missing"
        assert x86.index("Build Layer 2") < x86.index("tests/vm/boot-x86_64.sh") < x86.index("Build Layer 3"), "VM gate ordering invalid"
        assert "if: always()" in x86 and "output/evidence/vm-x86_64/" in x86, "VM evidence upload must survive failure"
        assert "tests/vm/boot-x86_64.sh" not in arm and "qemu-system-x86" not in arm, "VM gate must remain x86_64-only"
        vm_script = os.path.join(root, "tests/vm/boot-x86_64.sh")
        with open(vm_script) as f:
            vm = f.read()
        assert "TIMEOUT_SECONDS" in vm and "second<TIMEOUT_SECONDS" in vm, "VM gate must have a bounded timeout"
        assert "find_ovmf_code" in vm and "is_non_secure_code" in vm, "VM gate must use non-secure OVMF code selection"
        assert "if=pflash,format=raw,readonly=on" in vm and "QEMU_FIRMWARE_ARGS" in vm, "VM gate must use readonly pflash UEFI code"
        assert "OVMF_VARS" in vm and "cp --" in vm, "VM gate must copy matching VARS instead of mutating the template"
        assert '-bios "$OVMF"' not in vm, "pflash OVMF code must not be passed as -bios"
        assert "-serial stdio" in vm, "VM gate must use QEMU stdio serial capture"
        assert "-serial file:" not in vm, "VM gate must not use buffered serial file backend"
        assert "command -v stdbuf" in vm, "VM gate must preflight stdbuf"
        assert "stdbuf -o0 -e0 qemu-system-x86_64" in vm, "VM gate must launch QEMU through unbuffered stdbuf"
        assert '>"$SERIAL_LOG" 2>"$QEMU_LOG"' in vm, "VM gate must redirect QEMU stdout/stderr to separate evidence logs"
        assert "ASHIPAOS_BOOT_SUCCESS=1" in vm, "VM gate must require the deterministic boot marker"
        assert "kernel panic" in vm and "emergency mode" in vm, "VM gate must reject panic/emergency boots"
        assert "qemu-command.txt" in vm and "qemu-version.txt" in vm and "image.sha256" in vm, "VM evidence inputs missing"
        assert "SHUTDOWN_GRACE_SECONDS" in vm and "kill -KILL" in vm, "VM cleanup must have bounded graceful shutdown and force fallback"
        assert "MARKER_OBSERVED=0" in vm and "MARKER_OBSERVED=1" in vm, "VM gate must track marker-triggered shutdown explicitly"
        assert "OBSERVATION_TIMEOUT=0" in vm and "marker observed after bounded shutdown" in vm, "VM gate must inspect buffered serial after timeout shutdown"
        assert "0|137|143" in vm, "VM gate must accept only normal or expected marker shutdown statuses"
        assert "QEMU_STATUS == 0" in vm, "VM gate must reject nonzero QEMU exit without marker"
        assert "test-boot-x86_64-fake.sh" in os.listdir(os.path.join(root, "tests/vm")), "fake-QEMU regression test missing"
        layer2_script = open(os.path.join(root, "layers/layer2-image/scripts/build-image.sh")).read()
        assert "console=ttyS0,115200n8" in layer2_script, "x86_64 GRUB command line must expose ttyS0"
        grub_linux_lines = [line for line in layer2_script.splitlines() if "linux /" in line]
        grub_initrd_lines = [line for line in layer2_script.splitlines() if "initrd /" in line]
        assert len(grub_linux_lines) == 3 and all("linux /vmlinuz root=LABEL=$ROOT_LABEL ro console=tty0 console=ttyS0,115200n8" in line for line in grub_linux_lines), "x86_64 GRUB entries must retain Debian's root-level /vmlinuz and required console/root arguments"
        assert len(grub_initrd_lines) == 3 and all("initrd /initrd.img" in line for line in grub_initrd_lines), "x86_64 GRUB entries must use Debian's root-level /initrd.img"
        assert not any("linux /boot/vmlinuz " in line or "initrd /boot/initrd.img" in line for line in grub_linux_lines + grub_initrd_lines), "x86_64 GRUB entries must not use /boot kernel paths"
        assert "/boot/grub/grub.cfg" in layer2_script and "/root/boot/grub/grub.cfg" in layer2_script, "GRUB config must be written to canonical image paths"
        marker = open(os.path.join(root, "layers/layer1-rootfs/scripts/build-rootfs.sh")).read()
        assert 'local issue="$rootfs/etc/issue"' in marker, "boot marker must write rootfs /etc/issue"
        assert "printf 'ASHIPAOS_BOOT_SUCCESS=1\\n' >> \"$issue\"" in marker, "boot marker must append the exact banner line"
        assert 'if [[ "$product_arch" == "x86_64" || "$product_arch" == "amd64" ]]' in marker, "boot marker must enable x86_64 and amd64 aliases"
        marker_guard = next(line for line in marker.splitlines() if 'if [[ "$product_arch"' in line)
        assert '"arm64"' not in marker_guard and '"armhf"' not in marker_guard, "boot marker must remain disabled for ARM aliases"
        assert "ashipaos-boot-success.service" not in marker, "boot marker must not depend on a separate service"
        assert "multi-user.target.wants" not in marker, "boot marker must not use target service wiring"


print("test-workflow-files: PASS")
PYEOF

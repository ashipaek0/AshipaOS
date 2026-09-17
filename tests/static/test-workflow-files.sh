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
        assert "tests/vm/boot-x86_64.sh" in x86, "x86_64 VM gate missing"
        assert x86.index("Build Layer 2") < x86.index("tests/vm/boot-x86_64.sh") < x86.index("Build Layer 3"), "VM gate ordering invalid"
        assert "if: always()" in x86 and "output/evidence/vm-x86_64/" in x86, "VM evidence upload must survive failure"
        assert "tests/vm/boot-x86_64.sh" not in arm and "qemu-system-x86" not in arm, "VM gate must remain x86_64-only"
        vm_script = os.path.join(root, "tests/vm/boot-x86_64.sh")
        with open(vm_script) as f:
            vm = f.read()
        assert "TIMEOUT_SECONDS" in vm and "second<TIMEOUT_SECONDS" in vm, "VM gate must have a bounded timeout"
        assert "-bios \"$OVMF\"" in vm and "find_ovmf" in vm, "VM gate must use robust OVMF UEFI boot"
        assert "-serial \"file:$SERIAL_LOG\"" in vm, "VM gate must capture serial output"
        assert "ASHIPAOS_BOOT_SUCCESS=1" in vm, "VM gate must require the deterministic boot marker"
        assert "kernel panic" in vm and "emergency mode" in vm, "VM gate must reject panic/emergency boots"
        assert "qemu-command.txt" in vm and "qemu-version.txt" in vm and "image.sha256" in vm, "VM evidence inputs missing"
        assert "SHUTDOWN_GRACE_SECONDS" in vm and "kill -KILL" in vm, "VM cleanup must have bounded graceful shutdown and force fallback"
        assert "MARKER_OBSERVED=0" in vm and "MARKER_OBSERVED=1" in vm, "VM gate must track marker-triggered shutdown explicitly"
        assert "0|137|143" in vm, "VM gate must accept only normal or expected marker shutdown statuses"
        assert "QEMU_STATUS == 0" in vm, "VM gate must reject nonzero QEMU exit without marker"
        assert "test-boot-x86_64-fake.sh" in os.listdir(os.path.join(root, "tests/vm")), "fake-QEMU regression test missing"
        layer2_script = open(os.path.join(root, "layers/layer2-image/scripts/build-image.sh")).read()
        assert "console=ttyS0,115200n8" in layer2_script, "x86_64 GRUB command line must expose ttyS0"
        assert "/boot/grub/grub.cfg" in layer2_script and "/root/boot/grub/grub.cfg" in layer2_script, "GRUB config must be written to canonical image paths"
        assert "ashipaos-boot-success.service" in open(os.path.join(root, "layers/layer1-rootfs/scripts/build-rootfs.sh")).read(), "boot marker service missing"


print("test-workflow-files: PASS")
PYEOF

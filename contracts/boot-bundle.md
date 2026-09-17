# Boot bundle contract

For x86_64, the immutable Debian snapshot supplies `linux-image-amd64` and its
initramfs. `configure-rootfs.sh` records the resolved kernel version and rejects
an incomplete kernel/initramfs pair. No host kernel is copied.

The image assembler owns GPT creation, the EFI system partition, removable
GRUB installation, and `grub.cfg`. The target definition owns the kernel
command line and filesystem labels. The rootfs builder owns neither partitions
nor bootloader state. Device trees do not apply to this target.

The current development image does not implement coordinated kernel/rootfs
rollback. Therefore it must not be represented as a release candidate until
the declared rollback and upgrade tests pass.

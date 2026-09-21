# x86_64 Root Filesystem

Layer 1 builds the Debian amd64 root filesystem used by the x86_64 UEFI image. Kernel, initramfs, systemd, D-Bus, networking, and the runtime user are installed inside the target rootfs. Full image construction is CI-only.

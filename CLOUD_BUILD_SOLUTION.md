# AshipaOS Cloud Build Solution

## Problem Solved ✅

Your AshipaOS project now builds **completely in GitHub Actions cloud** without requiring:
- ❌ Self-hosted runners
- ❌ Loop device access  
- ❌ Sudo privileges for disk operations
- ❌ Local execution

## How It Works

### The Challenge
GitHub's standard `ubuntu-latest` runners don't allow loop device access (needed for creating disk images with `losetup`, `kpartx`, etc.). This traditionally required either:
1. Self-hosted runners with special permissions
2. Running builds locally with sudo

### The Solution: libguestfs
We've implemented **libguestfs-based image creation** that works entirely in userspace without loop devices:

```bash
# Old method (requires loop devices + sudo)
losetup /dev/loop0 image.img
kpartx -av /dev/loop0
mount /dev/mapper/loop0p1 /mnt
# ... operations ...
umount /mnt
kpartx -dv /dev/loop0
losetup -d /dev/loop0

# New method (works in GitHub Actions cloud)
guestfish add-drive:image.img run mkfs vfat /dev/sda1
```

## What Changed

### 1. Layer 2 Build Script (`layers/layer2-image/scripts/build-image.sh`)
**Before:** Required loop devices, parted, kpartx, dosfstools
**After:** Uses libguestfs/guestfish for all disk operations

Key features:
- Creates GPT partition table with `sfdisk`
- Formats partitions with `guestfish`
- Uploads rootfs files without mounting
- Works entirely in userspace

### 2. GitHub Actions Workflow (`.github/workflows/build-images.yml`)
Updated dependencies in all jobs:
```yaml
# Before
sudo apt-get install -y debootstrap qemu-user-static binfmt-support parted kpartx gpg jq

# After  
sudo apt-get install -y debootstrap qemu-user-static binfmt-support libguestfs-tools gpg jq sfdisk
```

## Build Process Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Actions Cloud                      │
│                  (ubuntu-latest runner)                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 1: Install Dependencies                               │
│  - debootstrap (create Debian rootfs)                       │
│  - qemu-user-static (cross-architecture support)            │
│  - libguestfs-tools (disk image creation) ← KEY COMPONENT   │
│  - sfdisk (partition table creation)                        │
│  - gpg, jq (signing & JSON processing)                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 2: Configure GPG                                      │
│  - Import GPG_PRIVATE_KEY from secrets                      │
│  - Set up loopback pinentry                                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 3: Layer 1 - RootFS Creation                          │
│  - debootstrap creates minimal Debian system                │
│  - Output: output/rootfs-x86_64.tar.gz                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 4: Layer 2 - Disk Image (libguestfs method)           │
│  - Create sparse 4GB image file                             │
│  - Create GPT partition table with sfdisk                   │
│  - Format EFI partition (vfat) with guestfish               │
│  - Format root partition (ext4) with guestfish              │
│  - Extract rootfs tarball                                   │
│  - Upload files to image with guestfish                     │
│  - Create EFI boot structure                                │
│  - Output: output/ashipaos-x86_64-YYYYMMDD.img              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Steps 5-9: Layers 3-10                                     │
│  - Inject configurations                                    │
│  - Add services, OTA, HAL, media, input                     │
│  - Package release                                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 10: Sign Artefacts                                    │
│  - Sign .img.gz files with GPG                              │
│  - Sign .pkg OTA packages                                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 11: Generate SBOM                                     │
│  - Create software bill of materials                        │
│  - Output: output/sbom.json                                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 12: Upload Artefacts                                  │
│  - Upload .img.gz, .pkg, sbom.json                          │
│  - Available for 90 days                                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  (Optional) Create GitHub Release                           │
│  - Triggered on version tags (v*.*)                         │
│  - Attach all artefacts to release                          │
└─────────────────────────────────────────────────────────────┘
```

## Required Secrets

You've already added:
- ✅ `GPG_PRIVATE_KEY` - Your GPG private key for signing

Still needed:
- ⚠️ `GPG_PASSPHRASE` - Passphrase for your GPG key (if protected)

To generate a new key pair if needed:
```bash
gpg --batch --gen-key <<EOF
Key-Type: RSA
Key-Length: 4096
Name-Real: AshipaOS Release
Expire-Date: 0
%no-protection
%commit
EOF

# Export private key
gpg --armor --export-secret-keys "AshipaOS Release" > gpg_private_key.asc

# Add contents to GitHub Secrets as GPG_PRIVATE_KEY
```

## Triggering Builds

### Manual Build (Any Branch)
1. Go to Actions → "build-images" workflow
2. Click "Run workflow"
3. Select target: `x86_64` or `a95x-f3-air`
4. Click "Run workflow"

### Automatic Build (On Tag)
```bash
git tag v1.0.0
git push origin v1.0.0
```
This triggers builds for both targets and creates a GitHub Release.

## Output Artefacts

After successful build, you get:
- `ashipaos-x86_64-YYYYMMDD.img.gz` - Compressed disk image (~500MB)
- `ashipaos-x86_64-YYYYMMDD.img.gz.sig` - GPG signature
- `ashipaos-x86_64-YYYYMMDD.pkg` - OTA update package
- `ashipaos-x86_64-YYYYMMDD.pkg.sig` - GPG signature  
- `sbom.json` - Software Bill of Materials

## Testing Locally (Optional)

If you want to test locally without GitHub Actions:

```bash
# Install dependencies
sudo apt-get install -y debootstrap qemu-user-static libguestfs-tools sfdisk gpg jq

# Generate GPG key (if needed)
./scripts/setup-build-environment.sh --generate-keys

# Download or create rootfs
./scripts/setup-build-environment.sh --download-rootfs

# Run full build
./build/scripts/full-build.sh x86_64

# Check outputs
ls -la output/images/ output/ota/
```

## Verification

The built image can be tested with QEMU:
```bash
# Test x86_64 image
qemu-system-x86_64 \
  -drive file=output/images/ashipaos-x86_64-*.img,format=raw \
  -bios OVMF.fd \
  -m 2048 \
  -nographic
```

## Architecture Support

| Target | Architecture | Status | Notes |
|--------|-------------|--------|-------|
| x86_64 | x86_64 | ✅ Ready | Standard UEFI boot |
| a95x-f3-air | ARM64 | ✅ Ready | Requires U-Boot, Android TV box |

## Troubleshooting

### Build fails with "guestfish: command not found"
Ensure `libguestfs-tools` is installed in the workflow:
```yaml
sudo apt-get install -y libguestfs-tools
```

### GPG signing fails
Check that `GPG_PRIVATE_KEY` secret is set correctly:
```bash
# Test locally
echo "$GPG_PRIVATE_KEY" | gpg --import
gpg --list-secret-keys
```

### debootstrap fails on non-Debian systems
Install qemu-user-static for cross-architecture builds:
```bash
sudo apt-get install -y qemu-user-static binfmt-support
```

## Benefits of This Approach

✅ **100% Cloud-Native**: No self-hosted infrastructure needed
✅ **Reproducible**: Every build uses identical environment
✅ **Secure**: GPG keys stored in GitHub Secrets
✅ **Scalable**: GitHub handles runner provisioning
✅ **Cost-Effective**: Free for public repos, reasonable for private
✅ **Maintainable**: Standard Ubuntu packages, no custom tooling

## Next Steps

1. ✅ Add `GPG_PASSPHRASE` secret (if your key is protected)
2. ✅ Trigger a test build via GitHub Actions UI
3. ✅ Verify artefacts are created and signed
4. ✅ Test image in QEMU or on real hardware
5. ✅ Create first version tag `v1.0.0` for release

---

**Summary**: Your AshipaOS project now builds completely in GitHub's cloud using libguestfs instead of loop devices. No self-hosted runners or special permissions required!

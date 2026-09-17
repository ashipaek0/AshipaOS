# AshipaOS Build Environment Setup Guide

## Overview

This guide explains how to set up your environment for building AshipaOS bootable images. The build system has three critical requirements that must be addressed:

1. **Loop Device Support** - Required for creating actual disk images (Layer 2)
2. **GPG Key Setup** - Required for signing release artefacts (Layer 10)
3. **Real Rootfs Creation** - Required as the base for all images (Layer 1)

## Quick Start

```bash
# Run the complete setup script
sudo ./scripts/setup-build-environment.sh --all

# Or run individual steps
./scripts/setup-build-environment.sh --check-status
sudo ./scripts/setup-build-environment.sh --install-deps
./scripts/setup-build-environment.sh --generate-keys
```

---

## Problem 1: Loop Device Support

### The Issue

Layer 2 (`build-image.sh`) creates bootable disk images by:
1. Creating a raw disk image file
2. Setting up partition tables with `parted`
3. Creating filesystems (vfat for EFI, ext4 for root)
4. Mounting partitions via loop devices
5. Extracting rootfs into the mounted partitions

**Problem:** Loop devices require kernel access that is:
- ❌ Unavailable in standard GitHub Actions runners
- ❌ Unavailable in unprivileged Docker containers
- ✅ Available on bare-metal self-hosted runners
- ✅ Available when running locally with root/sudo

### Solutions

#### Option A: Use Self-Hosted Runners (Recommended for CI/CD)

Set up a self-hosted runner on a machine with loop device access:

```bash
# On your self-hosted machine (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y qemu-utils parted kpartx dosfstools e2fsprogs

# Register as GitHub self-hosted runner
cd /opt
sudo mkdir actions-runner && cd actions-runner
curl -O -L https://github.com/actions/runner/releases/download/v2.317.0/actions-runner-linux-x64-2.317.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.317.0.tar.gz
sudo ./config.sh --url https://github.com/YOUR_ORG/YOUR_REPO --token YOUR_TOKEN
sudo ./svc.sh install
sudo ./svc.sh start
```

In your workflow, use:
```yaml
runs-on: [self-hosted, linux, privileged]
```

#### Option B: Use Privileged Docker Container (For Local Development)

```bash
# Build the builder container
cd ci/containers
docker build -f Dockerfile.builder -t ashipaos-builder .

# Run with privileged mode for loop device access
docker run --privileged -v /workspace:/workspace ashipaos-builder \
    ./build/scripts/full-build.sh x86_64
```

#### Option C: Metadata-Only Mode (For Testing Without Images)

The current Layer 2 script supports a metadata-only mode that doesn't require loop devices:

```bash
# This creates metadata files but no actual disk image
./layers/layer2-image/scripts/build-image.sh --no-loop rootfs.tar.gz x86_64
```

**Limitation:** This produces `.meta.json` files only, not bootable images.

#### Option D: Run Locally with Sudo (Fastest for Development)

```bash
# Install dependencies
sudo ./scripts/setup-build-environment.sh --install-deps

# Build images
sudo ./build/scripts/full-build.sh x86_64
```

---

## Problem 2: GPG Key Setup

### The Issue

Layer 10 and the signing script (`ci-sign-artefacts.sh`) sign all release artefacts:
- Disk images (`.img.gz.sig`)
- OTA packages (`.pkg.sig`)
- SBOM files (`.sbom.json.sig`)

**Problem:** Signing requires a GPG private key that must be:
- Securely stored (never committed to git)
- Available during CI builds
- Trusted for verification

### Solution: Generate and Configure GPG Keys

#### Step 1: Generate Keys Locally

```bash
./scripts/setup-build-environment.sh --generate-keys
```

This creates:
- `output/gpg_private_key.asc` - Private key for GitHub Secrets
- `output/gpg_passphrase.txt` - Passphrase (optional, key has no protection)
- `output/gpg_public_key.asc` - Public key for verification

#### Step 2: Add to GitHub Secrets

1. Go to your GitHub repository
2. Navigate to **Settings → Secrets and variables → Actions**
3. Click **New repository secret**
4. Add these secrets:

| Secret Name | Value |
|-------------|-------|
| `GPG_PRIVATE_KEY` | Contents of `output/gpg_private_key.asc` |
| `GPG_PASSPHRASE` | Contents of `output/gpg_passphrase.txt` (or leave empty) |

#### Step 3: Verify Signing Works

```bash
# Test locally
gpg --list-secret-keys "AshipaOS Release Bot"

# Test in CI by triggering a workflow
gh workflow run build-images.yml --ref main
```

#### Manual Key Generation (Alternative)

```bash
# Generate key pair
gpg --batch --gen-key <<EOF
%echo Generating AshipaOS Release Key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: AshipaOS Release Bot
Name-Email: release@ashipaos.local
Expire-Date: 0
%no-protection
%commit
EOF

# Export private key for GitHub Secrets
gpg --armor --export-secret-keys "release@ashipaos.local" > output/gpg_private_key.asc

# Export public key for distribution
gpg --armor --export "release@ashipaos.local" > output/gpg_public_key.asc
```

---

## Problem 3: Real Rootfs Creation

### The Issue

Layer 1 (`build-rootfs.sh`) creates a minimal Debian rootfs using `debootstrap`. This is the foundation for all disk images.

**Problem:** `debootstrap`:
- ❌ May not be installed on your system
- ❌ Requires root privileges
- ❌ Takes 5-10 minutes to download and extract packages
- ❌ Needs `qemu-user-static` for cross-architecture builds (e.g., building ARM on x86)

### Solutions

#### Option A: Install Dependencies and Build (Full Control)

```bash
# Install debootstrap and dependencies
sudo apt-get update
sudo apt-get install -y debootstrap qemu-user-static

# Build rootfs for x86_64
sudo ./layers/layer1-rootfs/scripts/build-rootfs.sh amd64 /workspace/output/rootfs-x86_64.tar.gz

# Build rootfs for ARM64 (requires qemu-user-static)
sudo ./layers/layer1-rootfs/scripts/build-rootfs.sh arm64 /workspace/output/rootfs-arm64.tar.gz
```

#### Option B: Download Pre-built Debian Cloud Image (Faster)

```bash
# Download pre-built Debian cloud image
./scripts/setup-build-environment.sh --download-rootfs amd64

# Use it with --skip-l1 flag
./build/scripts/full-build.sh --skip-l1 x86_64
```

This downloads official Debian cloud images from `cloud.debian.org`, which are:
- ✅ Pre-minimized for cloud/embedded use
- ✅ Already optimized for size
- ✅ Available for multiple architectures
- ✅ Updated regularly

#### Option C: Use Existing Rootfs (Development Iteration)

When iterating on Layers 2-10, skip Layer 1 entirely:

```bash
# First time: create rootfs
sudo ./layers/layer1-rootfs/scripts/build-rootfs.sh amd64 /workspace/output/rootfs-x86_64.tar.gz

# Subsequent builds: skip Layer 1
./build/scripts/full-build.sh --skip-l1 x86_64
```

---

## Complete Build Workflows

### Workflow 1: Full Build on Self-Hosted Runner (Production)

```yaml
# .github/workflows/build-images.yml
name: Build Images

on:
  push:
    tags: ['v*']
  workflow_dispatch:

jobs:
  build:
    runs-on: [self-hosted, linux, privileged]
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup environment
        run: sudo ./scripts/setup-build-environment.sh --install-deps
      
      - name: Import GPG key
        run: |
          echo "$GPG_PRIVATE_KEY" | gpg --import
        env:
          GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
      
      - name: Build full image
        run: sudo ./build/scripts/full-build.sh x86_64
        env:
          VERSION: ${{ github.ref_name }}
      
      - name: Upload artefacts
        uses: actions/upload-artifact@v4
        with:
          name: ashipaos-images
          path: output/images/*.img.gz
```

### Workflow 2: Local Development Build

```bash
# One-time setup
sudo ./scripts/setup-build-environment.sh --install-deps --generate-keys

# Build everything
sudo ./build/scripts/full-build.sh x86_64

# Iterate on Layers 3-10 (skip L1 and L2)
./build/scripts/full-build.sh --skip-l1 x86_64

# Check outputs
ls -la output/images/
ls -la output/ota/
cat output/sbom.json
```

### Workflow 3: Docker-Based Build (Isolated Environment)

```bash
# Build builder container
cd ci/containers
docker build -f Dockerfile.builder -t ashipaos-builder .

# Run build in container
docker run --rm --privileged \
  -v /workspace:/workspace \
  -e GPG_PRIVATE_KEY="$(cat /workspace/output/gpg_private_key.asc)" \
  ashipaos-builder \
  ./build/scripts/full-build.sh x86_64
```

---

## Verification Checklist

After setup, verify your environment:

```bash
./scripts/setup-build-environment.sh --check-status
```

Expected output:
```
✓ debootstrap: 1.34+deb12u1
✓ qemu-user-static: 8 binaries available
✓ parted: /usr/sbin/parted
✓ kpartx: /usr/sbin/kpartx
✓ mkfs.vfat: /usr/sbin/mkfs.vfat
✓ mkfs.ext4: /usr/sbin/mkfs.ext4
✓ GPG: gpg (GnuPG) 2.2.40
  └─ Signing key: READY
✓ Loop devices: AVAILABLE
✓ Docker: Docker version 24.0.7
  └─ Mode: Standard

✅ Environment is READY for building
```

---

## Troubleshooting

### Loop Device Errors

**Error:** `losetup: cannot find an unused loop device`

**Solution:**
```bash
# Increase max loop devices
sudo modprobe loop max_loop=16

# Or free up unused loop devices
sudo losetup -a | grep '(unused)' | cut -d: -f1 | xargs -I {} sudo losetup -d {}
```

### GPG Signing Fails

**Error:** `gpg: signing failed: No secret key`

**Solution:**
```bash
# Verify key is imported
gpg --list-secret-keys

# Re-import from file
gpg --import output/gpg_private_key.asc

# Set trust level
echo -e "5\ny\n" | gpg --batch --command-fd 0 --edit-key "AshipaOS Release Bot" trust
```

### Debootstrap Fails

**Error:** `debootstrap: command not found`

**Solution:**
```bash
# Install debootstrap
sudo apt-get update && sudo apt-get install -y debootstrap

# Or use downloaded rootfs instead
./scripts/setup-build-environment.sh --download-rootfs amd64
./build/scripts/full-build.sh --skip-l1 x86_64
```

### Cross-Architecture Build Fails

**Error:** `qemu-user-static: not found`

**Solution:**
```bash
# Install qemu-user-static
sudo apt-get install -y qemu-user-static

# Verify binaries are available
ls /usr/bin/qemu-*-static
```

---

## Summary: What You Need to Provide

| Requirement | What to Provide | How |
|-------------|----------------|-----|
| **Loop Devices** | Self-hosted runner OR local sudo access | Set up self-hosted runner with loop device access, or run locally with `sudo` |
| **GPG Key** | GPG private key in GitHub Secrets | Run `./scripts/setup-build-environment.sh --generate-keys` and add to Secrets |
| **Rootfs** | Either debootstrap OR downloaded image | Run `sudo ./scripts/setup-build-environment.sh --install-deps` OR `--download-rootfs` |

### Minimal Setup Commands

```bash
# 1. Install dependencies
sudo ./scripts/setup-build-environment.sh --install-deps

# 2. Generate GPG keys
./scripts/setup-build-environment.sh --generate-keys

# 3. Add GPG_PRIVATE_KEY to GitHub Secrets (manual step)
#    Copy contents of output/gpg_private_key.asc to GitHub

# 4. Build!
sudo ./build/scripts/full-build.sh x86_64
```

---

## Next Steps

After successful build:

1. **Test the image** in QEMU:
   ```bash
   qemu-system-x86_64 -drive file=output/images/ashipaos-x86_64-*.img.gz,format=raw
   ```

2. **Deploy to hardware** (if you have physical devices)

3. **Configure OTA updates** using the generated `.pkg` files

4. **Set up automated releases** with GitHub Actions

For more details, see:
- `docs/GITHUB_SECRETS_SETUP.md` - Detailed secrets configuration
- `CI_CD_ACTIVATION_CHECKLIST.md` - Complete CI/CD setup checklist
- `README.md` - Project overview

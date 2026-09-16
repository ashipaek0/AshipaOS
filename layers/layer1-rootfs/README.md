# Layer 1: Minimal Debian Root Filesystem

## Overview
This layer provides a minimal Debian root filesystem builder for multiple architectures (arm64, amd64, armhf).

## Verification Class
**BUILD** - Requires debootstrap and potentially qemu-user-static for cross-architecture builds.

## Directory Structure
```
layer1-rootfs/
├── scripts/
│   └── build-rootfs.sh      # Main build script
├── config/
│   └── rootfs-config.yaml   # Configuration file
├── tests/
│   └── static-tests.sh      # Static verification tests
└── evidence/                 # Build evidence storage
```

## Usage

### Building a Root Filesystem
```bash
# Basic usage
./scripts/build-rootfs.sh <target_arch> <output_file>

# Examples
./scripts/build-rootfs.sh arm64 /workspace/output/rootfs-arm64.tar.gz
./scripts/build-rootfs.sh amd64 /workspace/output/rootfs-amd64.tar.gz
./scripts/build-rootfs.sh armhf /workspace/output/rootfs-armhf.tar.gz
```

### Environment Variables
- `DEBIAN_SUITE`: Debian suite (default: bookworm)
- `DEBIAN_MIRROR`: Debian mirror URL (default: http://deb.debian.org/debian)
- `COMPONENTS`: Debian components (default: main,contrib,non-free-firmware)

### Running Static Tests
```bash
./tests/static-tests.sh
```

## Requirements
- debootstrap
- qemu-user-static (for cross-architecture builds only)
- bash 4.0+

## Configuration
Edit `config/rootfs-config.yaml` to customize:
- Debian suite and mirror
- Package lists
- Exclusion patterns
- Size limits
- Verification requirements

## Evidence Generation
The build script automatically generates JSON evidence files in the `evidence/` directory containing:
- Build parameters
- Artefact information
- Builder environment details
- Timestamp

## Invariants
1. No hardware-specific values hardcoded in build scripts
2. Architecture passed as parameter
3. Verification class BUILD properly documented
4. Evidence generated for every build
5. Shell standards compliance (set -euo pipefail)

## Outputs
- Root filesystem tarball (`.tar.gz`)
- Build evidence JSON file

## Next Steps
After building the rootfs, proceed to Layer 2 for kernel integration.

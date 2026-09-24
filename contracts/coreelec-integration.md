# A95X F3 Air CoreELEC integration contract

This contract applies only to `a95x-f3-air`. It records the evidence-backed
CoreELEC baseline and the boundaries for replacing Kodi with Jellyfin MPV Shim.
It does not claim that the replacement integration has been built or exercised
on hardware.

## Relationship to the current image build

The `build-images` workflow currently ships a Debian trixie arm64 image
booted by the box's vendor U-Boot (see `boot-bundle.md`) straight into
Jellyfin MPV Shim via `ashipaos-jellyfin-mpv-shim.service`. CoreELEC is the
evidence-backed baseline for this target: the `coreelec-ce2a` workflow builds
and inspects the pinned stock image as prerequisite evidence only. Nothing
from the CoreELEC image is copied into the AshipaOS image, and the rules below
govern any future CoreELEC-based integration.

## Evidence-backed baseline

| Item | Status | Evidence |
|---|---|---|
| CoreELEC source | `CONFIRMED` | `ashipaek0/CoreELEC`, tag `21.3-Omega`, commit `fc61125e8900ab0c2593a29b615980ed0cd5b939`; source archive SHA256 `c31d4d047682915190fbfc16b46134e7d0a6bb8a119edee59a31b0b2b332a73a` |
| CoreELEC build tuple | `CONFIRMED` | `PROJECT=Amlogic-ce`, `DEVICE=Amlogic-ng`, `ARCH=arm`, `OFFICIAL=yes`; artifact `CoreELEC-Amlogic-ng.arm-21.3-Omega-Generic.img.gz` |
| Target DTB | `CONFIRMED` | `sm1_s905x3_4g.dtb`, copied to the FAT boot-partition root and renamed `dtb.img` |
| Amlogic-ng options | `CONFIRMED` | `Image.lzo`, `kernel.img`, `DISPLAYSERVER=no`, `OPENGLES=opengl-meson`, `ALSA_SUPPORT=yes`, `KODIPLAYER_DRIVER=libamcodec`, `AMREMOTE_SUPPORT=yes` |
| CoreELEC Python | `CONFIRMED` | version `3.11.9` |
| ffmpeg | `CONFIRMED` | version `6.0.1` |
| mpv-drmprime | `CONFIRMED` | package version `0.38.0`; DRM/GBM/EGL-DRM support and its declared dependencies are present |
| Kodi inclusion seam | `CONFIRMED` | Kodi package/service is the current package and service inclusion seam; it is not an approved runtime for AshipaOS |
| Jellyfin MPV Shim source | `CONFIRMED` | tag `v3.0.0`, commit `9970b2dc4a91f0c96a9fa5a1fcecf6a69331e315`; archive SHA256 `c27b8ae2d698a152052586149b30b3125d82f9ac7695d2b32ca865ef6bd7f731` |
| Jellyfin MPV Shim requirements | `CONFIRMED` | Python `>=3.9`; `python-mpv>=1.0.8`, `jellyfin-apiclient-python>=1.18.0`, `python-mpv-jsonipc>=1.4.0`, `requests`, `pillow`; entrypoint `jellyfin-mpv-shim` |

These facts describe the pinned stock CoreELEC baseline and source metadata.
They are not proof of AshipaOS post-replacement behavior.

## Integration contract

### No-Kodi package graph

- Kodi must be excluded before image construction. It must not be installed and
  deleted afterward.
- The final package manifest and image must contain no Kodi executable, package
  payload, Kodi-only library, add-on, configuration, unit, launcher, autostart
  path, update/recovery reference, or fallback.
- The dependency graph must be closed from the retained package set: no retained
  package may pull Kodi back in transitively. The Kodi package/service inclusion
  seam is the exclusion point to inspect and test.
- The current CoreELEC Kodi service is not a launcher contract for AshipaOS.
  Jellyfin MPV Shim is the only approved user-facing runtime.

### Runtime bridge and media path

- Direct DRM/GBM using the pinned `mpv-drmprime` package is the leading
  **candidate**, because DRM/GBM/EGL-DRM support is evidenced. It is not a
  confirmed final selection.
- No final bridge, compositor, launcher, `hwdec` value, display mode, audio
  route, input route, or decoder result is proven by this inventory.
- Do not add cage, Wayland, another compositor, or a replacement kernel/
  firmware/DTB/graphics/audio/network/decode stack unless pinned-source,
  build, and exact-target probes establish the need and compatibility.
- The final choice requires target-equivalent probes and hardware evidence for
  render initialization, display, audio, input, playback, and claimed hardware
  decode. In particular, no 10-bit HEVC or other codec claim is currently
  proven.

### Package graph closure

The implementation must publish and verify a graph containing, at minimum:

1. CoreELEC-provided Python `3.11.9`, ffmpeg `6.0.1`, mpv/libmpv, and the
   selected `mpv-drmprime`/native libraries;
2. the pinned Jellyfin MPV Shim source and its resolved Python dependencies;
3. all transitive native and Python dependencies, with provider, version, and
   ABI information;
4. the Kodi exclusion report and a scan proving no forbidden Kodi artefact;
5. the entrypoint `jellyfin-mpv-shim` and its readiness/failure behavior.

The bundle must be built in CI for the CoreELEC ABI. Production devices must
consume only a signed, hashed, CI-built bundle; they must not run `pip`, compile
source, check out Git, or resolve dependencies from PyPI.

### Persistence and service boundaries

- CoreELEC owns the immutable OS image, boot, kernel, firmware, DTB, graphics,
  audio, network, and hardware-support stack.
- AshipaOS owns only its package/overlay delta, the Jellyfin MPV Shim bundle,
  and its service integration. The application updater must never mutate the
  CoreELEC system image.
- The service must start the released Jellyfin MPV Shim built-in library/
  browser UI full-screen, with no visible Kodi or general-purpose desktop.
- Configuration, Jellyfin credentials, identity, cache, downloads, logs, and
  updater state belong under protected persistent `/storage` paths, outside
  the OS image and application bundles.
- The service must use a documented unprivileged user and only the device/group
  permissions proven necessary by probes. No final user, group, device, or
  privilege selection is currently proven.
- Startup ordering, bounded restart behavior, writable-slot selection, known-
  good rescue behavior, and an application-level readiness signal must be
  explicit in the implementation and statically checked.

## Evidence classes and gates

- `STATIC` / `github-actions`: pin, archive hashes, target metadata, package
  graph, Kodi exclusion, service/persistence declarations, and contract shape.
- `BUILD` / `github-actions`: target-equivalent ABI probes, resolved dependency
  closure, bundle contents, signatures, and final image scan.
- `HARDWARE` / `hardware-lab`: boot with `dtb.img`, direct runtime/compositor
  decision, display/audio/input/network behavior, playback, and hardware decode.
- `MANUAL` / `human`: visible full-screen appliance UX and diagnosable failure
  state.

A missing hardware runner blocks the applicable gate; it does not turn a
candidate bridge or runtime claim into a pass.

## Explicit unknowns

The following remain `UNKNOWN` for AshipaOS integration and must not be
silently promoted by this contract:

- final DRM/GBM bridge, compositor, launcher, and `hwdec` configuration;
- final display, audio, input, CEC, IR, remote, and decoder behavior;
- final service user, groups, device permissions, and privilege boundary;
- final package selection and complete transitive closure after Kodi removal;
- Python/native ABI compatibility of the complete Jellyfin MPV Shim bundle;
- service startup, persistence, slot selection, rescue, readiness, and failure
  behavior on the exact target;
- AshipaOS boot, Wi-Fi, Bluetooth, Ethernet, storage, and general runtime
  behavior after replacement integration.

The confirmed DTB and pinned CoreELEC baseline must not be downgraded because
these replacement-integration questions remain open.

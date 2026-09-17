# Release readiness

The automated pipelines now reach reproducible **development prerelease
builds** for x86_64 and an Amlogic/CoreELEC hardware baseline. They do not yet
authorize a stable release or release candidate.

| Layer | Automated state | Remaining gate |
|---|---|---|
| 1 — rootfs | Built from a pinned Debian snapshot; package and kernel versions recorded | CI build evidence |
| 2 — base system | systemd, non-root UI user, identity reset, time sync, and base services configured | VM service assertions |
| 3 — display | cage and mpv installed; hardened display unit supplied | Application payload and physical display evidence |
| 4 — network/storage | ConnMan, storage partition, mount contract, and firewall supplied | Provisioning and network hardware tests |
| 5 — application | Slot-aware launcher fails closed when no validated application exists | Pinned Jellyfin application payload |
| 6 — input | Standard Linux input permissions supplied | CEC/IR hardware evidence |
| 7 — settings | Not implemented | Protocol, daemon, authorization, and negative tests |
| 8/8.5 — updates | Not implemented | OS/app update state machines and rollback tests |
| 9 — distribution | Compressed GPT/UEFI image, checksum, and manifest generated | Physical installation evidence |
| 10 — release | Deterministic metadata, image inspection, and QEMU boot gate implemented | Upgrade, rollback, security, and hardware acceptance |

The Amlogic pipeline builds the pinned CoreELEC `Amlogic-ng` Generic image on a
dedicated `ashipaos-builder` runner. Version `0.0.1-dev` retains Kodi on purpose:
it establishes the stock-compatible boot baseline required before replacing
the media stack. Its DTB and all hardware behavior remain provisional.

The release manifest deliberately records hardware verification as `blocked`.
The release workflow publishes both tracks as a GitHub **prerelease** only after
their build checks pass. Stable publishing must remain disabled until every
remaining release gate in the build guide has evidence.

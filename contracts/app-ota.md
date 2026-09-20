# App OTA contract — Jellyfin MPV Shim

## Scope and ownership

The Layer 5 application updater owns only the Jellyfin MPV Shim A/B slots under `/storage/apps/jellyfin-mpv-shim`. Layer 3 continues to own the display service and compositor. Layer 6 owns the OS OTA mechanism and must not rewrite application slots.

## Artifact requirements

An application artifact is accepted only for x86_64 and only when it records:

- name `jellyfin-mpv-shim` and version `3.0.0` or a later approved version;
- source commit and archive SHA-256;
- exact dependency lock and SBOM entries containing artifact filename, SHA-256, Python tag, ABI tag, and platform tag;
- mandatory upstream dependencies derived from `pyproject.toml`;
- no optional systray/gui/discord extras and no Windows `pywin32`;
- no Debian `python3-mpv`, whose ABI is incompatible with this application contract.

The current CI bundle verifies the pinned v3.0.0 source archive and emits unresolved dependency metadata. It must refuse activation until a target-compatible exact lock is present; it must not invent versions or hashes.

## Transaction and recovery

1. Download to a temporary file and verify the declared digest.
2. Extract and validate the manifest, entry point, dependency lock, and executable closure.
3. Install into the inactive slot with ownership `ashipa:ashipa` and restrictive permissions.
4. Validate the complete slot before atomically replacing `active.json`.
5. On restart, select only A or B and a validated executable. If validation fails, use the immutable bundle; if it is unavailable, report a visible/logged recoverable error and exit nonzero.
6. Never delete the last valid slot before the new selector is durable. No credentials or logs are included in artifacts.

Rollback is the inverse atomic selector change and does not modify the immutable image or Layer 3 service.

# Storage contract — Jellyfin MPV Shim application state

## Ownership

Layer 5 application owns only the Jellyfin MPV Shim application state below. Layer 3 owns the display compositor/session and must launch the validated Layer 5 launcher; it must not own application slots or credentials.

## Paths and permissions

- `/usr/lib/ashipaos/apps/jellyfin-mpv-shim/3.0.0`: immutable image bundle, root-owned, read-only at runtime.
- `/storage/jellyfin-mpv-shim`: persistent configuration and credentials, mode `0700`, owner `ashipa:ashipa`; never populated by the image build.
- `/storage/apps/jellyfin-mpv-shim/slots/A` and `slots/B`: persistent OTA slots, each containing a complete validated executable bundle.
- `/storage/apps/jellyfin-mpv-shim/active.json`: atomically replaced selector, owner `ashipa:ashipa`, mode `0600`.

`active.json` is valid only when it is JSON with exactly `{"slot":"A"|"B","version":"..."}`. Parsers reject traversal, arbitrary paths, unknown slots, and malformed JSON. A write uses a same-directory temporary file, `fsync`, and `rename`.

The image contains no Jellyfin credentials, tokens, logs, cache, downloads, or generated active selector. Missing or invalid persistent state is recoverable: the launcher attempts the immutable bundle, otherwise emits a visible error and exits nonzero. It never starts idle mpv or a test video.

## Target boundary

This contract applies only to the Debian `x86_64` target. It does not alter A95X/CoreELEC storage or ownership.

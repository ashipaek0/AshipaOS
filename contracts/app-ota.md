# A95X application OTA contract

Jellyfin MPV Shim is baked into its root slot's filesystem at image-build
time (`layers/layer5-application/scripts/build-application.sh`), from a
hash-pinned dependency lock and a source archive verified against a pinned
GitHub commit. There is no separate, in-place application update mechanism:
shipping a new application version means shipping a new root slot, and it
uses exactly the OS update mechanism in `contracts/os-ota.md` (write the
passive slot, mark it pending, let the boot-time state machine confirm or
revert it).

This was a deliberate simplification over an earlier design that kept
independently-selectable application "slots" inside a single root filesystem
(`active.json` plus a `slots/` directory owned by the `ashipa` service
user). That design let the application update itself without an OS update,
but at the cost of a weaker trust boundary: the same `ashipa` user the
application runs as could write to its own slot directory, so a compromised
or buggy application process could tamper with what the launcher would run
next. The current design instead installs the application bundle read-only
and owned by root (`/usr/lib/ashipaos/apps/jellyfin-mpv-shim`,
`layers/layer5-application/files/usr/libexec/ashipaos-jellyfin-mpv-shim`
validates its ownership and manifest hash before executing it), and relies on
the whole-slot OS update path for any change to it.

Requirements carried over from the application's own dependency pinning
(`layers/layer5-application/config/dependencies.lock.json` and
`layers/layer5-application/scripts/jellyfin-bundle.py`), independent of how a
slot reaches the device: every dependency artifact is hash-pinned and
verified before use; the installed source is proven byte-identical to a
pinned GitHub commit; the bundle is validated against the target arm64/cp313
ABI tags before installation; and no runtime package resolver, network
access, or reusable plaintext credential is used to install or run it.

See `contracts/os-ota.md` for what "shipping a new root slot" actually
requires, including the update-delivery step that does not exist yet.

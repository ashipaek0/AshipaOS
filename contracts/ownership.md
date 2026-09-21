# x86_64 Ownership Boundaries

The x86_64 target owns the UEFI/GPT image, Debian root filesystem, systemd services, display session, application bundle, release artifacts, and OTA metadata. The image builder must preserve ownership and mode contracts for the `ashipa` runtime user.

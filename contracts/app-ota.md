# x86_64 Application and OTA Contract

The x86_64 image contains a pinned, hash-verified Jellyfin MPV Shim bundle under `/usr/lib/ashipaos/apps/` and its launcher under `/usr/libexec/`.

OTA artifacts are published under `output/ota/` with a manifest and SHA-256 checksum. The release pipeline must sign the image and OTA artifacts and publish the SBOM alongside them.

# Storage contract

The image assembler owns the physical GPT layout. The x86_64 storage
partition is ext4, labelled `ashipaos-storage`, and mounted at `/storage`.
The rootfs builder only declares the mount and directory expectations.

Layout version 1 contains `config`, `state`, `cache`, `downloads`,
`thumbnails`, `logs`, and `app`. Configuration and state are private to uid
1000 (`ashipaos`); caches and thumbnails are safe to purge; the application
directory is root-owned because only the future application updater may
activate slots there.

Boot continues when storage is absent, but `ashipaos-storage.service` and the
display application fail closed. A corrupt or full filesystem is never
silently reformatted. Factory reset and layout migration are not implemented,
so a release candidate must report those acceptance gates as blocked.

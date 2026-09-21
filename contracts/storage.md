# x86_64 Storage Contract

The x86_64 image uses a GPT disk with a vFAT EFI partition and an ext4 root partition labelled `RootFS`. Persistent application state is kept under `/storage`; immutable application content is kept under `/usr/lib/ashipaos/apps/`.

The image builder must preserve ownership and modes for the `ashipa` runtime user and must not embed reusable plaintext credentials.

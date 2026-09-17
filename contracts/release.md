# Release contract

`assemble-image.sh` emits a compressed target image, SHA-256 checksum, and JSON
manifest. The build ID derives from the Git source commit and hashes of the
target/package inputs; it never uses the wall clock.

A generated artefact is a **development build** until its manifest evidence is
updated by CI and all required VM and hardware gates pass. Hardware, display,
Jellyfin application, provisioning, OTA, rollback, and upgrade validation are
currently blocked or pending; automation must not publish these images as a
stable release or release candidate.

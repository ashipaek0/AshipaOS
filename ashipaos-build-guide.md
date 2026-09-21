# A95X F3 Air Build Guide

## Scope

This branch builds only the Amlogic A95X F3 Air appliance. CoreELEC provenance, pinned source validation, boot image inspection, DTB handling, and removable-SD safety are part of this track.

## Required gates

1. Validate the pinned CoreELEC source and checksum.
2. Build and inspect the prerequisite image in GitHub Actions.
3. Validate the A95X boot files, DTB, partition table, FAT16 boot filesystem, and ext4 root filesystem.
4. Build the AshipaOS image through the CI workflow.
5. Test only on removable SD media; never overwrite eMMC.
6. Use 3.3 V TTL UART without connecting VCC; never use RS-232 voltage.

The exact hardware runtime and Jellyfin playback gates remain hardware evidence, not claims inferred from static tests.

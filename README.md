# AshipaOS offline appliance installer

AshipaOS is a Debian 13 amd64 Jellyfin MPV Shim appliance. Its hybrid BIOS/UEFI ISO contains a prebuilt disk image and an offline, unattended installer—not Debian Installer or a network-dependent package setup.

Installation overwrites exactly one eligible disk. It fails closed on ambiguous or unsafe targets, including the installer medium. Only a blank disk is installable: a completed installation is never overwritten, so reinstalling means wiping the disk first. The installed system starts Jellyfin MPV Shim through greetd and labwc, with SSH-key-only administration.

Image construction and BIOS/UEFI VM validation run in GitHub Actions. Physical display, GPU, audio, input, suspend, and playback still require hardware testing.

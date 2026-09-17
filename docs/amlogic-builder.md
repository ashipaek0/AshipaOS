# Amlogic builder

The CoreELEC build must run on a dedicated, unprivileged Linux account. Register
the machine as a GitHub Actions self-hosted runner with these labels:

```text
self-hosted, linux, x64, ashipaos-builder
```

Minimum allocation is 16 GiB RAM and 100 GiB free disk. The workflow enforces
an 80 GiB available-workspace floor after checkout to allow up to 20 GiB for
the runner, checkout, and tool overhead; this does not reduce the 100 GiB
provisioning requirement. The runner account may use passwordless `sudo
apt-get` only for installing the host tools declared in
`build/config/coreelec-host-packages.txt`; the preflight and CoreELEC build both
refuse uid 0.

Before assigning the runner label, install the declared packages and run the
same preflight used by the release workflow:

```bash
mapfile -t packages < <(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' build/config/coreelec-host-packages.txt)
sudo apt-get update
sudo apt-get install --yes "${packages[@]}"
build/scripts/preflight-amlogic-builder.sh
```

For a clean manual build:

```bash
build/scripts/build-amlogic.sh 0.0.1-dev
tests/build/test-amlogic-image.sh
```

Outputs are written to `build/output/amlogic/`. Only the Generic image is
published because the named upstream subdevice images target unrelated boards.
Do not install the Generic image to eMMC. Select and verify a DTB on removable
media, capture a serial log, and update the box facts with that evidence.

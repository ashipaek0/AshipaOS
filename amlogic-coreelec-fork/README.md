# CoreELEC source checkout

The Amlogic track uses a reproducible, detached CoreELEC checkout as required
by build-guide Task 0.5.2. The source-controlled pin is in
`build/targets/amlogic/boxes/a95x-f3-air.yaml`; upstream source is materialized
under `amlogic-coreelec-fork/source/` and is intentionally ignored by Git.

Create or verify the checkout with:

```bash
build/scripts/checkout-coreelec.sh
```

The script refuses a tag that does not resolve to the recorded full commit,
an existing checkout with the wrong origin, a non-detached checkout, or local
changes. Delete the generated `source/` directory to recreate it from the pin.

The source tree alone is not the AshipaOS integration. To apply the
source-controlled development package and build the selected Generic Amlogic
image as an unprivileged user, run:

```bash
build/scripts/build-amlogic.sh 0.0.1-dev
```

See `docs/amlogic-builder.md` for runner requirements and hardware caveats.

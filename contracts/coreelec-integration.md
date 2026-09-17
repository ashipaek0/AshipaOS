# CoreELEC integration contract

```yaml
coreelec_integration:
  coreelec_ref: 21.3-Omega
  coreelec_commit: fc61125e8900ab0c2593a29b615980ed0cd5b939
  project: Amlogic-ce
  device: Amlogic-ng
  package_system: CoreELEC package.mk
  service_manager: systemd
  overlay_mechanism: package makeinstall_target
  kodi_removal_method: not-yet-applied
  retained_services:
    - kodi.service
  disabled_services: []
  replaced_services: []
  input_stack: CoreELEC Amlogic-ng defaults
  cec_stack: CoreELEC Amlogic-ng defaults
  ir_stack: CoreELEC Amlogic-ng defaults
  network_stack: connman
  update_conflicts: not-yet-evaluated
```

Version `0.0.1-dev` is deliberately a stock-compatible hardware-baseline
image. The source-controlled `ashipaos-dev-baseline` package adds build identity
and a boot evidence marker without claiming that Kodi has been replaced.

The `Amlogic-ng` selection is based on the S905X3 generation and the options
available in the pinned source tree, but remains `PROVISIONAL`. A working DTB,
serial boot evidence, and hardware acceptance are required before this image is
promoted beyond a development prerelease.

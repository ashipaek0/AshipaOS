# Hardware fact status and evidence rules (build guide §1.5)

Hardware facts MUST be labelled:

- `CONFIRMED`: directly verified on the target or from authoritative
  project/device documentation adopted by the repository.
- `PROVISIONAL`: plausible but not yet verified.
- `UNKNOWN`: not established.

`PROVISIONAL` and `UNKNOWN` values MUST NOT become silent architectural
dependencies.

Hardware facts must include evidence. Example (unverified):

```yaml
wifi:
  driver: null
  status: UNKNOWN
  evidence: []
```

After testing, the fact records the verified value with evidence artefacts,
e.g. command output and test logs under
`evidence/amlogic/<box>/<subsystem>/`.

A hardware fact MUST be reviewed again when any of the following change:
kernel branch, CoreELEC ref, device tree, firmware, box configuration,
rootfs base, or driver package set.

A hardware fact without evidence is not a confirmed fact.

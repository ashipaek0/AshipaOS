#!/usr/bin/env bash
set -Eeuo pipefail
for f in scripts/*.sh installer/*.sh provision/appliance-session provision/appliance-shell provision/appliance-health-check provision/appliance-update provision/validate-admin-key.sh; do
  [ -f "$f" ] || continue
  bash -n "$f"
done
for f in tests/*.sh; do bash -n "$f"; done
[ -x installer/select-target.sh ] && [ -x installer/install.sh ]
! grep -RInE 'BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|password[[:space:]]*=[[:space:]]*[^<${]' . --exclude-dir=.git --exclude='*.md'
printf '%s\n' 'AshipaOS static checks: PASS'

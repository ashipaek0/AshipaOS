#!/usr/bin/env bash
set -Eeuo pipefail
key=${1:?usage: validate-flatpak-key.sh KEY_FILE FINGERPRINT [IDENTITY]}
fingerprint=${2:?expected primary key fingerprint}
identity=${3:-}
[[ -s "$key" ]] || { echo 'Flathub signing key file is missing' >&2; exit 1; }
info=$(gpg --batch --show-keys --with-colons "$key") || { echo 'cannot inspect Flathub signing key' >&2; exit 1; }
python3 -c '
import sys
expected, identity = sys.argv[1:]
rows = [line.rstrip("\n").split(":") for line in sys.stdin]
primary_count = 0
primary_fingerprints = []
awaiting_primary_fingerprint = False
uids = []
for row in rows:
    kind = row[0]
    if kind == "pub":
        primary_count += 1
        awaiting_primary_fingerprint = True
    elif kind == "sub":
        awaiting_primary_fingerprint = False
    elif kind == "fpr" and awaiting_primary_fingerprint:
        primary_fingerprints.append(row[9].upper())
        awaiting_primary_fingerprint = False
    elif kind == "uid":
        uids.append(row[9])
if primary_count != 1 or primary_fingerprints != [expected.upper()]:
    raise SystemExit("Flathub keyring must contain exactly the pinned primary key")
if identity and not any(identity in uid for uid in uids):
    raise SystemExit("Flathub signing key identity mismatch")
' "$fingerprint" "$identity" <<<"$info"
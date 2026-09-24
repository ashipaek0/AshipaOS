#!/usr/bin/env python3
"""Print the refs of a Flatpak lock, one per line, after checking its origin."""
import json
import sys

lock = json.load(open(sys.argv[1]))
if lock.get('collection_id') != 'org.flathub.Stable' or not lock.get('refs'):
    raise SystemExit('Flatpak lock is not a nonempty org.flathub.Stable graph')
for row in lock['refs']:
    print(row['ref'])

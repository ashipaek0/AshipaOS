#!/usr/bin/env python3
"""Lock the collection refs actually present in a Flatpak create-usb export."""
import json
import re
import subprocess
import sys

repo, app_ref, app_commit, runtime_ref, runtime_commit = sys.argv[1:]
listed = subprocess.check_output(
    ['ostree', 'refs', '--collections', '--revision', f'--repo={repo}'], text=True
)
refs = []
metadata_refs = []
seen_refs = set()
for line in listed.splitlines():
    match = re.fullmatch(r'\(([^,]+), ([^)]+)\)\t([0-9a-f]{64})', line)
    if not match:
        raise SystemExit(f'unrecognized ostree collection-ref listing: {line!r}')
    collection_id, ref, commit = match.groups()
    if collection_id != 'org.flathub.Stable':
        raise SystemExit(f'unexpected create-usb collection ID: {collection_id!r}')
    if ref in seen_refs:
        raise SystemExit(f'duplicate create-usb ref: {ref!r}')
    seen_refs.add(ref)
    if re.fullmatch(r'appstream2/(?:x86_64|aarch64|i386|arm|armv7)', ref):
        metadata_refs.append({'collection_id': collection_id, 'ref': ref, 'commit': commit})
    elif re.fullmatch(r'(?:app|runtime)/[A-Za-z0-9._-]+/(?:x86_64|aarch64|i386|arm|armv7)/[A-Za-z0-9._-]+', ref):
        refs.append({'collection_id': collection_id, 'ref': ref, 'commit': commit})
    else:
        raise SystemExit(f'unexpected create-usb ref: {ref!r}')
if not refs:
    raise SystemExit('create-usb exported no collection refs')
by_ref = {row['ref']: row['commit'] for row in refs}
if len(by_ref) != len(refs):
    raise SystemExit('duplicate create-usb refs')
for ref, commit in ((app_ref, app_commit), (f'runtime/{runtime_ref}', runtime_commit)):
    if by_ref.get(ref) != commit:
        raise SystemExit(f'create-usb missing or mismatched installed ref: {ref}')
print(json.dumps({'collection_id': 'org.flathub.Stable',
                  'app': 'com.github.iwalton3.jellyfin-mpv-shim',
                  'refs': refs, 'metadata_refs': metadata_refs}, sort_keys=True))

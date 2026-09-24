#!/usr/bin/env python3
"""Verify an exact Flatpak ref-to-commit lock against installed rows."""
import json
import re
import sys

def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)

REF_RE = re.compile(r'(?:app|runtime)/[A-Za-z0-9][A-Za-z0-9._-]*/(?:x86_64|aarch64|i386|arm|armv7)/[A-Za-z0-9][A-Za-z0-9._-]*\Z')

if len(sys.argv) != 3:
    fail('usage: verify-flatpak-lock.py LOCK INSTALLED_TSV')
lock_path, installed_path = sys.argv[1:3]
try:
    rows = json.load(open(lock_path))['refs']
except (OSError, ValueError, KeyError, TypeError) as error:
    fail(f'invalid lock: {error}')
if not isinstance(rows, list):
    fail('lock refs must be a list')
lock = {}
for row in rows:
    if (not isinstance(row, dict) or not isinstance(row.get('ref'), str) or not REF_RE.fullmatch(row['ref'])
            or not isinstance(row.get('commit'), str) or not re.fullmatch(r'[0-9a-fA-F]{64}', row['commit'])):
        fail('malformed lock ref or commit')
    if row['ref'] in lock:
        fail(f'duplicate lock ref: {row["ref"]}')
    lock[row['ref']] = row['commit']
actual = {}
try:
    with open(installed_path) as installed:
        for number, line in enumerate(installed, 1):
            fields = line.rstrip('\n').split('\t')
            if len(fields) != 2 or not REF_RE.fullmatch(fields[0]) or not re.fullmatch(r'[0-9a-fA-F]{64}', fields[1]):
                fail(f'malformed installed row {number}')
            if fields[0] in actual:
                fail(f'duplicate installed ref: {fields[0]}')
            actual[fields[0]] = fields[1]
except OSError as error:
    fail(f'cannot read installed refs: {error}')
missing = sorted(set(lock) - set(actual))
wrong = sorted(ref for ref, commit in lock.items() if actual.get(ref) != commit)
extra = sorted(set(actual) - set(lock))
if missing or wrong or extra:
    print(f'missing={missing} wrong={wrong} extra={extra}', file=sys.stderr)
    raise SystemExit(1)

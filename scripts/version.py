#!/usr/bin/env python3
"""Single source of release version; stamp both bundles without changing their IDs."""
import argparse
import plistlib
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
version = (root / 'VERSION').read_text().strip()
if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version):
    raise SystemExit('VERSION must be a numeric major.minor.patch version')
parser = argparse.ArgumentParser()
parser.add_argument('--stamp', type=Path)
parser.add_argument('--check-tag')
args = parser.parse_args()
if args.check_tag and args.check_tag != f'v{version}':
    raise SystemExit(f'Tag must match VERSION: v{version}')
if args.stamp:
    with args.stamp.open('rb') as source:
        info = plistlib.load(source)
    info['CFBundleShortVersionString'] = version
    info['CFBundleVersion'] = version
    with args.stamp.open('wb') as destination:
        plistlib.dump(info, destination)
print(version)

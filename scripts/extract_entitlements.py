#!/usr/bin/env python3
"""Extract Entitlements plist from an iOS provisioning profile."""
import argparse
from pathlib import Path
import plistlib
import re
import sys

def extract_entitlements(provision_path: Path, output_path: Path):
    content = provision_path.read_bytes()
    match = re.search(rb'<\?xml.*?</plist>', content, re.DOTALL)
    entitlements = {}
    if match:
        data = plistlib.loads(match.group(0))
        entitlements = data.get('Entitlements', {})
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open('wb') as f:
        plistlib.dump(entitlements, f)
    print('已提取 Entitlements:', entitlements)
    return entitlements

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('provision_path', type=Path, help='Path to .mobileprovision file')
    parser.add_argument('output_path', type=Path, help='Path to output entitlements.plist')
    args = parser.parse_args()
    if not args.provision_path.is_file():
        raise FileNotFoundError(f'Provisioning profile not found: {args.provision_path}')
    extract_entitlements(args.provision_path, args.output_path)

if __name__ == '__main__':
    main()

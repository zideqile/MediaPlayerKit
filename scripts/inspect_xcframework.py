#!/usr/bin/env python3
"""Structural audit only; does not prove link/runtime dependency closure."""
import argparse, json, plistlib, re
from pathlib import Path

def inspect(root):
    data = plistlib.loads((root / 'Info.plist').read_bytes())
    slices = []
    for item in data.get('AvailableLibraries', []):
        framework = root / item['LibraryIdentifier'] / item['LibraryPath']
        if not framework.is_dir(): raise ValueError('missing framework: ' + str(framework))
        interfaces = list(framework.rglob('*.swiftinterface'))
        if not interfaces: raise ValueError('missing Swift interface: ' + str(framework))
        if not (framework / framework.stem).is_file(): raise ValueError('missing framework executable')
        if not list(framework.rglob('vzplayer-bridge.js')): raise ValueError('missing JS bridge resource')
        imports = set()
        for source in interfaces:
            imports.update(re.findall(r'\bimport\s+(?:class\s+|struct\s+)?([A-Za-z_]\w*)', source.read_text()))
        exposed = imports.intersection({'KSPlayer', 'FFmpegKit', 'DisplayCriteria'})
        if exposed: raise ValueError('SDK exposes source dependency modules: '+', '.join(sorted(exposed)))
        slices.append({'identifier': item['LibraryIdentifier'], 'platform': item.get('SupportedPlatform'),
                       'variant': item.get('SupportedPlatformVariant', 'device'),
                       'architectures': item.get('SupportedArchitectures', []), 'imports': sorted(imports)})
    if not any(x['platform']=='ios' and x['variant']=='device' and 'arm64' in x['architectures'] for x in slices):
        raise ValueError('missing iOS arm64 device slice')
    if not any(x['platform']=='ios' and x['variant']=='simulator' and 'arm64' in x['architectures'] for x in slices):
        raise ValueError('missing iOS arm64 simulator slice')
    return {'status': 'CANDIDATE_NOT_RUNTIME_VERIFIED', 'slices': slices,
            'note': 'Imports and otool output require dependency closure review and binary consumer validation.'}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xcframework', type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect(args.xcframework), indent=2))

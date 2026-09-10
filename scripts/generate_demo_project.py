#!/usr/bin/env python3
"""Generate an SDK-only, source Demo, or binary-only Demo XcodeGen spec."""
import argparse
import copy
import json
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]

def configure(base, mode, sdk, platform):
    spec = copy.deepcopy(base)
    if mode == 'sdk':
        spec['targets'].pop('MediaPlayerKitDemo')
        spec['name'] = 'MediaPlayerKitSDK'
        return spec
    if mode == 'source':
        return spec
    if mode != 'binary': raise ValueError('invalid dependency mode')
    if not (sdk/'MediaPlayerKit.xcframework/Info.plist').is_file():
        raise ValueError('SDK binary missing; build SDK first or select --mode source')
    spec['name'] = 'MediaPlayerKitDemoBinary'
    spec.pop('packages', None)
    spec['targets'].pop('MediaPlayerKit')
    demo = spec['targets']['MediaPlayerKitDemo']
    frameworks = sorted(sdk.glob('*.xcframework'))
    demo['dependencies'] = [{'framework': str(p.resolve()), 'embed': True} for p in frameworks]
    # All XCFramework dependencies emitted by the packager here are dynamic; static libs are inside the SDK.
    resources = sdk/'Resources'/platform
    if resources.exists():
        for resource in sorted(resources.glob('*.bundle')):
            demo['sources'].append({'path': str(resource.resolve()), 'type': 'file', 'buildPhase': 'resources'})
    return spec

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['sdk','source','binary'])
    parser.add_argument('--sdk-dir', type=Path)
    parser.add_argument('--platform', choices=['device','simulator'])
    args = parser.parse_args()
    defaults = json.loads((ROOT/'Config/DemoBuild.json').read_text())
    sdk = args.sdk_dir or Path(defaults['sdkDirectory'])
    if not sdk.is_absolute(): sdk=ROOT/sdk
    spec=configure(yaml.safe_load((ROOT/'project.yml').read_text()), args.mode or defaults['mode'], sdk,
                   args.platform or defaults['platform'])
    # Keep the spec at repository root so original relative source/config paths remain correct.
    (ROOT/'project.generated.yml').write_text(yaml.safe_dump(spec, sort_keys=False, allow_unicode=True))
    print(spec['name']+'.xcodeproj')

if __name__ == '__main__': main()

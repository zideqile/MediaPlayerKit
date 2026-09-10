#!/usr/bin/env python3
"""Collect dynamic XCFramework dependencies and platform resource bundles from SDK builds."""
import argparse
import plistlib
import shutil
import subprocess
from pathlib import Path

def dependencies(binary):
    output = subprocess.check_output(['xcrun','otool','-L',str(binary)], text=True)
    return [line.strip().split(' (')[0] for line in output.splitlines() if line.startswith('\t')]

def collect(out):
    sdk=out/'SDK'
    pending=[sdk/'MediaPlayerKit.xcframework']
    seen=set()
    while pending:
        xc=pending.pop()
        if xc.name in seen: continue
        seen.add(xc.name)
        info=plistlib.loads((xc/'Info.plist').read_bytes())
        for entry in info['AvailableLibraries']:
            if entry.get('SupportedPlatform') != 'ios': continue
            fw=xc/entry['LibraryIdentifier']/entry['LibraryPath']
            for dep in dependencies(fw/fw.stem):
                if dep.startswith(('/System/Library/','/usr/lib/','@rpath/libswift')): continue
                if '.framework/' not in dep:
                    raise ValueError('Unpackaged non-system dependency: '+dep)
                name=dep.split('.framework/')[0].split('/')[-1]
                if name==fw.stem: continue # dylib install name
                target=sdk/(name+'.xcframework')
                if not target.exists():
                    candidates=list((out/'SourcePackages/artifacts').rglob(name+'.xcframework'))
                    if len(candidates)!=1:
                        raise ValueError(f'Cannot uniquely resolve {dep}; found {len(candidates)} artifacts')
                    shutil.copytree(candidates[0],target,symlinks=True)
                pending.append(target)
    for platform, suffix in [('device','iphoneos'),('simulator','iphonesimulator')]:
        destination=sdk/'Resources'/platform
        destination.mkdir(parents=True,exist_ok=True)
        for bundle in (out/('DerivedData-'+platform)).rglob('*.bundle'):
            if not any(part in (suffix, 'Release-'+suffix) for part in bundle.parts): continue
            resolved = bundle.resolve()
            if not resolved.exists() or not resolved.is_dir(): continue
            target=destination/bundle.name
            if not target.exists(): shutil.copytree(resolved,target,symlinks=True)
        if not any('KSPlayer' in p.name for p in destination.glob('*.bundle')):
            raise ValueError(f'Missing KSPlayer resource bundle for {platform}')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('output',type=Path)
    collect(p.parse_args().output)

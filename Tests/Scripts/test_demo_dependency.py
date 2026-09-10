import importlib.util
import tempfile
import unittest
from pathlib import Path
import yaml

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('demo',ROOT/'scripts/generate_demo_project.py')
demo=importlib.util.module_from_spec(spec)
spec.loader.exec_module(demo)

class DemoDependencyTests(unittest.TestCase):
    def setUp(self):
        self.base=yaml.safe_load((ROOT/'project.yml').read_text())
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.sdk=Path(self.temp.name)
    def test_binary_mode_rejects_missing_sdk(self):
        with self.assertRaisesRegex(ValueError,'SDK binary missing'):
            demo.configure(self.base,'binary',self.sdk,'device')
    def test_binary_mode_has_no_sdk_target_or_source_packages(self):
        fw=self.sdk/'MediaPlayerKit.xcframework'
        fw.mkdir();(fw/'Info.plist').write_text('fixture')
        (self.sdk/'Resources/device/KSPlayer_KSPlayer.bundle').mkdir(parents=True)
        spec=demo.configure(self.base,'binary',self.sdk,'device')
        self.assertNotIn('packages',spec)
        self.assertEqual(list(spec['targets']),['MediaPlayerKitDemo'])
        target=spec['targets']['MediaPlayerKitDemo']
        self.assertTrue(all('framework' in d for d in target['dependencies']))
        self.assertTrue(any('KSPlayer_KSPlayer.bundle' in s['path'] for s in target['sources']))
        self.assertNotIn('Sources/MediaPlayerKit',str(spec))
    def test_source_and_sdk_modes_are_separate(self):
        source=demo.configure(self.base,'source',self.sdk,'device')
        self.assertEqual(source['targets']['MediaPlayerKitDemo']['dependencies'],[{'target':'MediaPlayerKit'}])
        sdk=demo.configure(self.base,'sdk',self.sdk,'device')
        self.assertEqual(list(sdk['targets']),['MediaPlayerKit'])
        self.assertEqual(len(self.base['targets']),2)
    def test_simulator_uses_only_simulator_resources(self):
        fw=self.sdk/'MediaPlayerKit.xcframework';fw.mkdir();(fw/'Info.plist').touch()
        for platform in ['device','simulator']:
            (self.sdk/f'Resources/{platform}/KSPlayer.bundle').mkdir(parents=True)
        spec=demo.configure(self.base,'binary',self.sdk,'simulator')
        self.assertIn('/Resources/simulator/',str(spec))
        self.assertNotIn('/Resources/device/',str(spec))

if __name__=='__main__': unittest.main()

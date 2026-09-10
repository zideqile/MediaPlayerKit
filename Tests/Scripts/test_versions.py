import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('versions', Path(__file__).resolve().parents[2] / 'scripts/generate_versions.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class VersionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'SDK_VERSION').write_text('1.2.3')
        (self.root / 'DEMO_VERSION').write_text('2.0.1')
    def test_independent_versions_and_build_metadata(self):
        files = module.outputs(self.root, '218', 'abcdef1234', 'v1.2.3', '20260910183000(UTC+8)')
        self.assertIn('"1.2.3"', files['Sources/MediaPlayerKit/API/SDKVersion.swift'])
        self.assertIn('"2.0.1"', files['Examples/MediaPlayerKitDemo/DemoVersion.swift'])
        self.assertIn('CURRENT_PROJECT_VERSION = 218', files['Config/Versions.xcconfig'])
    def test_rejects_wrong_tag_and_untraceable_release(self):
        for build, commit, tag in [('1', 'abcdef1', 'v2.0.1'), ('0', 'development', 'v1.2.3')]:
            with self.assertRaises(ValueError): module.outputs(self.root, build, commit, tag)
    def test_rejects_invalid_version_and_injected_metadata(self):
        for version in ['01.2.3', '1.2', '1.2.3\nBAD']:
            (self.root / 'SDK_VERSION').write_text(version)
            with self.assertRaises(ValueError): module.outputs(self.root)
        (self.root / 'SDK_VERSION').write_text('1.2.3')
        for build, commit in [('-1', 'abcdef1'), ('1', '"bad')]:
            with self.assertRaises(ValueError): module.outputs(self.root, build, commit)
    def test_build_version_contains_date_commit_and_number(self):
        self.assertEqual(module.full_version('1.2.3', '218', 'abcdef1234567890', '20260910183000(UTC+8)'),
                         '1.2.3+20260910183000(UTC+8).abcdef123456.218')
        for date in ['20260230183000(UTC+8)', '2026-09-10', '20260910T103000Z', 'bad']:
            with self.assertRaises(ValueError): module.outputs(self.root, '1', 'abcdef1', build_date=date)

    def test_beijing_time_rolls_over_date_from_utc(self):
        utc = module.datetime(2026, 9, 10, 20, 30, tzinfo=module.timezone.utc)
        self.assertEqual(module.build_timestamp(utc), '20260911043000(UTC+8)')

    def test_development_output_is_deterministic(self):
        self.assertEqual(module.outputs(self.root), module.outputs(self.root))
        self.assertIn('isDevelopment = true', module.outputs(self.root)['Sources/MediaPlayerKit/API/SDKVersion.swift'])

if __name__ == '__main__': unittest.main()

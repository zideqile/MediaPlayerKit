import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('audit', Path(__file__).resolve().parents[2]/'scripts/inspect_xcframework.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

class AuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        libraries = []
        for ident, variant in [('ios-arm64', None), ('ios-arm64-simulator', 'simulator')]:
            framework = self.root/ident/'MediaPlayerKit.framework'
            framework.mkdir(parents=True)
            (framework/'MediaPlayerKit').write_bytes(b'fixture-not-a-real-binary')
            (framework/'api.swiftinterface').write_text('import Foundation\n')
            (framework/'vzplayer-bridge.js').write_text('// fixture')
            lib = dict(LibraryIdentifier=ident, LibraryPath='MediaPlayerKit.framework', SupportedPlatform='ios', SupportedArchitectures=['arm64'])
            if variant: lib['SupportedPlatformVariant'] = variant
            libraries.append(lib)
        (self.root/'Info.plist').write_bytes(plistlib.dumps({'AvailableLibraries': libraries}))
    def test_reports_imports_without_claiming_runtime_validation(self):
        result = audit.inspect(self.root)
        self.assertIn('NOT_RUNTIME_VERIFIED', result['status'])
        self.assertIn('Foundation', result['slices'][0]['imports'])
    def test_exposed_source_dependency_fails(self):
        next(self.root.rglob('*.swiftinterface')).write_text('import KSPlayer\n')
        with self.assertRaisesRegex(ValueError, 'source dependency'): audit.inspect(self.root)
    def test_missing_bridge_resource_fails(self):
        next(self.root.rglob('vzplayer-bridge.js')).unlink()
        with self.assertRaisesRegex(ValueError, 'JS bridge'): audit.inspect(self.root)
    def test_missing_swift_interface_fails(self):
        next(self.root.rglob('*.swiftinterface')).unlink()
        with self.assertRaisesRegex(ValueError, 'Swift interface'): audit.inspect(self.root)
    def test_device_only_fails(self):
        p=self.root/'Info.plist'
        data=plistlib.loads(p.read_bytes())
        data['AvailableLibraries']=data['AvailableLibraries'][:1]
        p.write_bytes(plistlib.dumps(data))
        with self.assertRaisesRegex(ValueError, 'simulator'): audit.inspect(self.root)

if __name__ == '__main__': unittest.main()

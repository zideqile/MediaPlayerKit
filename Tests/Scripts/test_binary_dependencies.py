import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('deps',Path(__file__).resolve().parents[2]/'scripts/collect_binary_dependencies.py')
deps=importlib.util.module_from_spec(spec);spec.loader.exec_module(deps)
class DependencyCollectionTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.out=Path(self.temp.name)
        self.make_framework(self.out/'SDK/MediaPlayerKit.xcframework','MediaPlayerKit')
        for platform,suffix in [('device','iphoneos'),('simulator','iphonesimulator')]:
            (self.out/f'DerivedData-{platform}/Build/Products/Release-{suffix}/KSPlayer_KSPlayer.bundle').mkdir(parents=True)
    def make_framework(self,root,name):
        (root/f'ios-arm64/{name}.framework').mkdir(parents=True)
        (root/'Info.plist').write_bytes(plistlib.dumps({'AvailableLibraries':[{'LibraryIdentifier':'ios-arm64','LibraryPath':name+'.framework','SupportedPlatform':'ios','SupportedArchitectures':['arm64']}]}))
    def test_copies_dynamic_dependency_and_platform_resources(self):
        self.make_framework(self.out/'SourcePackages/artifacts/vendor/Extra.xcframework','Extra')
        def links(binary):
            if binary.name=='MediaPlayerKit':return [
                '@rpath/MediaPlayerKit.framework/MediaPlayerKit',
                '@rpath/libswift_Concurrency.dylib',
                '@rpath/Extra.framework/Extra'
            ]
            return ['@rpath/Extra.framework/Extra','/usr/lib/libSystem.B.dylib']
        with patch.object(deps,'dependencies',links):deps.collect(self.out)
        self.assertTrue((self.out/'SDK/Extra.xcframework/Info.plist').exists())
        self.assertTrue((self.out/'SDK/Resources/simulator/KSPlayer_KSPlayer.bundle').is_dir())
    def test_missing_dynamic_dependency_fails(self):
        with patch.object(deps,'dependencies',return_value=['@rpath/Missing.framework/Missing']):
            with self.assertRaisesRegex(ValueError,'Cannot uniquely resolve'):deps.collect(self.out)
    def test_missing_resource_fails(self):
        p=self.out/'DerivedData-device/Build/Products/Release-iphoneos/KSPlayer_KSPlayer.bundle';p.rmdir()
        with patch.object(deps,'dependencies',return_value=[]):
            with self.assertRaisesRegex(ValueError,'resource bundle'):deps.collect(self.out)
if __name__=='__main__':unittest.main()

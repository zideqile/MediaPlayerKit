import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('extract_entitlements', Path(__file__).resolve().parents[2]/'scripts/extract_entitlements.py')
extract_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extract_mod)

class EntitlementsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_extract_entitlements_success(self):
        mock_entitlements = {
            "application-identifier": "TEAMID.com.example.app",
            "get-task-allow": False
        }
        xml_plist = plistlib.dumps({"Entitlements": mock_entitlements})
        # Simulate signed mobileprovision with CMS header/footer surrounding XML plist
        content = b"BINARY_HEADER" + xml_plist + b"BINARY_FOOTER"
        prov_file = self.root / "profile.mobileprovision"
        prov_file.write_bytes(content)
        out_file = self.root / "build/entitlements.plist"

        res = extract_mod.extract_entitlements(prov_file, out_file)
        self.assertEqual(res, mock_entitlements)
        self.assertTrue(out_file.is_file())
        with out_file.open('rb') as f:
            loaded = plistlib.load(f)
        self.assertEqual(loaded, mock_entitlements)

    def test_extract_entitlements_empty_when_no_xml(self):
        prov_file = self.root / "empty.mobileprovision"
        prov_file.write_bytes(b"NO_XML_DATA")
        out_file = self.root / "out.plist"
        res = extract_mod.extract_entitlements(prov_file, out_file)
        self.assertEqual(res, {})
        self.assertTrue(out_file.is_file())

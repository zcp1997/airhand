import importlib.util
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("verify_ipa", Path(__file__).parents[1] / "verify-ipa.py")
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


def binary(minimum=0x00100600, platform=2, cpu=0x0100000C, link=None):
    commands = struct.pack("<6I", 0x32, 24, platform, minimum, 0x001B0200, 0)
    if link is not None:
        command, name = link
        data = name.encode() + b"\0"
        size = (24 + len(data) + 7) // 8 * 8
        commands += struct.pack("<6I", command, size, 24, 0, 0, 0) + data + b"\0" * (size - 24 - len(data))
    return struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 1 + (link is not None), len(commands), 0, 0) + commands


class VerifyIPATests(unittest.TestCase):
    def test_device_binary_accepts_high_sdk_with_low_minimum(self):
        self.assertEqual(verify.validate_macho(binary())[0]["minimum"], "16.6.0")

    def test_new_minimum_simulator_wrong_architecture_and_truncation_fail(self):
        for data in [binary(minimum=0x00110000), binary(platform=7), binary(cpu=0x01000007), binary()[:-2]]:
            with self.assertRaises((ValueError, struct.error)):
                verify.validate_macho(data)

    def test_observation_must_be_weak_linked(self):
        name = "/System/Library/Frameworks/Observation.framework/Observation"
        with self.assertRaises(ValueError):
            verify.validate_macho(binary(link=(0xC, name)))
        self.assertEqual(len(verify.validate_macho(binary(link=(0x80000018, name)))), 1)

    def test_only_existing_app_group_entitlement_is_accepted(self):
        expected = {"com.apple.security.application-groups": [verify.GROUP]}
        verify.validate_entitlements(expected)
        for extra in ["get-task-allow", "platform-application", "com.apple.private.security.no-sandbox"]:
            with self.assertRaises(ValueError):
                verify.validate_entitlements({**expected, extra: True})
        with self.assertRaises(ValueError):
            verify.validate_entitlements({"com.apple.security.application-groups": ["wrong"]})

    def test_missing_extension_cannot_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / "missing.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/Airhand.app/Info.plist", plistlib.dumps({}))
            with self.assertRaisesRegex(ValueError, "broadcast extension"):
                verify.verify(ipa)

    def test_zip_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / "escape.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/../../escape", b"bad")
            with self.assertRaises(ValueError):
                verify.extract(ipa, Path(directory) / "unpacked")

    def test_bundle_metadata_requires_matching_identity_and_minimum(self):
        info = {"CFBundleIdentifier": verify.APP_ID, "CFBundleExecutable": "Airhand", "MinimumOSVersion": "16.6", "AirhandAppGroup": verify.GROUP, "AirhandBroadcastExtension": verify.EXTENSION_ID}
        self.assertEqual(verify.validate_plist(info, verify.APP_ID), "Airhand")
        for key, value in [("MinimumOSVersion", "17.0"), ("AirhandAppGroup", "other"), ("CFBundleExecutable", "../escape")]:
            with self.assertRaises(ValueError):
                verify.validate_plist({**info, key: value}, verify.APP_ID)


if __name__ == "__main__":
    unittest.main()

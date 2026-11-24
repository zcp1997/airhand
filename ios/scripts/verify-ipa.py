#!/usr/bin/env python3
"""Fail closed on an iOS 16.6 candidate IPA; also exposes pure checks for host tests."""
import argparse
import hashlib
import json
import plistlib
import shutil
import stat
import struct
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

TARGET = (16, 6, 0)
GROUP = "group.app.airhand.ios"
APP_ID = "app.airhand.ios"
EXTENSION_ID = APP_ID + ".broadcast"
MAGICS = {b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xce", b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def version(value):
    parts = tuple(int(v) for v in str(value).split("."))
    require(1 <= len(parts) <= 3, "invalid system version")
    return parts + (0,) * (3 - len(parts))


def packed_version(value):
    return (value >> 16, (value >> 8) & 255, value & 255)


def validate_plist(info, bundle_id, extension=False):
    require(info.get("CFBundleIdentifier") == bundle_id, "unexpected bundle identifier")
    require(version(info.get("MinimumOSVersion", "0")) == TARGET, "MinimumOSVersion must be 16.6")
    executable = info.get("CFBundleExecutable")
    require(isinstance(executable, str) and executable and PurePosixPath(executable).name == executable, "invalid executable name")
    require(info.get("AirhandAppGroup") == GROUP, "Info.plist App Group mismatch")
    if extension:
        require(info.get("NSExtension", {}).get("NSExtensionPointIdentifier") == "com.apple.broadcast-services-upload", "missing ReplayKit upload extension")
    else:
        require(info.get("AirhandBroadcastExtension") == EXTENSION_ID, "broadcast identifier mismatch")
    return executable


def validate_entitlements(entitlements):
    require(set(entitlements) == {"com.apple.security.application-groups"}, "unexpected or missing entitlement")
    require(entitlements["com.apple.security.application-groups"] == [GROUP], "App Group entitlement mismatch")


def validate_macho(data, label="Mach-O"):
    require(len(data) >= 4 and data[:4] in MAGICS, f"{label}: not a supported Mach-O")
    magic = data[:4]
    if magic in {b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}:
        endian = ">" if magic[:1] == b"\xca" else "<"
        count = struct.unpack_from(endian + "I", data, 4)[0]
        wide = magic in {b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}
        require(0 < count <= 16, f"{label}: invalid architecture count")
        reports = []
        for index in range(count):
            base = 8 + index * (32 if wide else 20)
            values = struct.unpack_from(endian + ("IIQQII" if wide else "IIIII"), data, base)
            offset, size = values[2:4]
            require(size > 0 and offset + size <= len(data), f"{label}: invalid architecture range")
            reports += validate_macho(data[offset:offset + size], label)
        return reports
    require(magic in {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"}, f"{label}: 32-bit device code is not supported")
    endian = "<" if magic == b"\xcf\xfa\xed\xfe" else ">"
    _, cpu, subtype, kind, commands, command_size, _, _ = struct.unpack_from(endian + "8I", data, 0)
    require(cpu == 0x0100000C and (subtype & 0xFFFFFF) in {0, 1}, f"{label}: requires baseline arm64 device code")
    require(kind in {2, 6, 8}, f"{label}: unexpected Mach-O file type")
    require(0 < commands <= 4096 and 32 + command_size <= len(data), f"{label}: invalid command region")
    offset = 32
    minimum = None
    platform = None
    for _ in range(commands):
        cmd, size = struct.unpack_from(endian + "II", data, offset)
        require(size >= 8 and offset + size <= 32 + command_size, f"{label}: invalid load command")
        if cmd == 0x32:
            require(size >= 24, f"{label}: invalid build version")
            platform, raw_minimum = struct.unpack_from(endian + "II", data, offset + 8)
            minimum = packed_version(raw_minimum)
        elif cmd == 0x25:
            minimum = packed_version(struct.unpack_from(endian + "I", data, offset + 8)[0])
            platform = 2
        elif cmd in {0xC, 0x80000018, 0x8000001F, 0x80000023}:
            require(size >= 24, f"{label}: malformed dylib command")
            name_offset = struct.unpack_from(endian + "I", data, offset + 8)[0]
            require(24 <= name_offset < size, f"{label}: invalid dylib name")
            name = data[offset + name_offset:offset + size].split(b"\0", 1)[0].decode("utf-8")
            if "Observation.framework/" in name or "libswiftObservation.dylib" in name:
                require(cmd == 0x80000018, f"{label}: Observation must be weak linked for iOS 16")
        offset += size
    require(offset == 32 + command_size, f"{label}: command size mismatch")
    require(platform == 2, f"{label}: non-device iOS platform {platform}")
    require(minimum is not None and minimum <= TARGET, f"{label}: minimum system exceeds 16.6")
    return [{"file": label, "architecture": "arm64", "platform": "iOS", "minimum": ".".join(map(str, minimum))}]


def extract(ipa, destination):
    with zipfile.ZipFile(ipa) as archive:
        names = set()
        require(sum(item.file_size for item in archive.infolist()) <= 1024 * 1024 * 1024, "IPA exceeds extraction limit")
        for item in archive.infolist():
            path = PurePosixPath(item.filename)
            require(not path.is_absolute() and ".." not in path.parts and "\\" not in item.filename, "unsafe IPA path")
            require(path.parts and path.parts[0] == "Payload", "unexpected top-level IPA content")
            require(item.filename not in names, "duplicate IPA entry")
            names.add(item.filename)
            mode = item.external_attr >> 16
            require(not stat.S_ISLNK(mode), "IPA symbolic links are not expected")
            target = destination.joinpath(*path.parts)
            if item.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(item) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
                target.chmod(mode & 0o777 or 0o644)


def verify(ipa):
    with tempfile.TemporaryDirectory(prefix="airhand-ipa-") as directory:
        root = Path(directory)
        extract(ipa, root)
        app = root / "Payload/Airhand.app"
        require(list((root / "Payload").iterdir()) == [app], "expected one Airhand app")
        extension = app / "PlugIns/AirhandBroadcast.appex"
        require(extension.is_dir() and list((app / "PlugIns").iterdir()) == [extension], "missing or unexpected broadcast extension")
        for bundle, identifier, is_extension in [(app, APP_ID, False), (extension, EXTENSION_ID, True)]:
            with (bundle / "Info.plist").open("rb") as source:
                info = plistlib.load(source)
            executable = validate_plist(info, identifier, is_extension)
            require((bundle / executable).is_file(), "bundle executable is missing")
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)], check=True, capture_output=True)
            signature = subprocess.run(["codesign", "-dv", str(bundle)], check=True, capture_output=True, text=True)
            require("Signature=adhoc" in signature.stderr, "expected ad-hoc candidate signature")
            result = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(bundle)], check=True, capture_output=True)
            validate_entitlements(plistlib.loads(result.stdout))
        reports = []
        banned = {".p12", ".pfx", ".pem", ".key", ".log", ".mobileprovision", ".xcresult"}
        for path in sorted(app.rglob("*")):
            if not path.is_file():
                continue
            require(path.suffix.lower() not in banned and path.name not in {"protocol.json", "settings.json", "identity.json", "Package.resolved"}, f"unexpected sensitive/build file: {path.name}")
            with path.open("rb") as source:
                magic = source.read(4)
                if magic in MAGICS:
                    reports += validate_macho(magic + source.read(), str(path.relative_to(root)))
        require(any(item["file"].endswith("/Airhand") for item in reports), "main executable is not Mach-O")
        require(any(item["file"].endswith("/AirhandBroadcast") for item in reports), "extension executable is not Mach-O")
        return {"sha256": hashlib.sha256(ipa.read_bytes()).hexdigest(), "binaries": reports, "device_validation": "NOT RUN: iOS 16.6.1 + TrollStore required"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    arguments = parser.parse_args()
    try:
        print(json.dumps(verify(arguments.ipa), ensure_ascii=False, indent=2))
    except (ValueError, OSError, KeyError, struct.error, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        parser.exit(1, f"IPA verification failed: {error}\n")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Reject credential material and generated files from the proposed compatibility diff."""
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[2]
changed = subprocess.check_output(["git", "diff", "--name-only", "-z", "08e2db0251760f04af40143f3d7409fdf9f16659", "--"], cwd=root).decode().split("\0")
untracked = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard", "-z"], cwd=root).decode().split("\0")
patterns = [re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"), re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b")]
for name in sorted(set(changed + untracked) - {""}):
    path = root / name
    if not path.is_file():
        continue
    if any(part.endswith((".xcodeproj", ".xcworkspace")) for part in Path(name).parts):
        raise SystemExit(f"generated Xcode project proposed for commit: {name}")
    if path.suffix.lower() in {".ipa", ".p12", ".pfx", ".key", ".pem", ".log", ".mobileprovision", ".pyc"} or path.name in {"identity.json", "settings.json", "devices.json"}:
        raise SystemExit(f"sensitive or generated file proposed for commit: {name}")
    if any(pattern.search(path.read_bytes()) for pattern in patterns):
        raise SystemExit(f"credential material proposed for commit: {name}")
print("Compatibility source diff contains no credential material or generated artifacts")

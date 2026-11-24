#!/usr/bin/env python3
"""Compare dependency identities and immutable states, ignoring root graph originHash."""
import json
import sys
from pathlib import Path

def pins(path):
    return sorted((pin["identity"], pin["state"]["revision"], pin["state"].get("version")) for pin in json.loads(Path(path).read_text())["pins"])

expected = pins(Path(__file__).parents[1] / "Package.resolved")
assert any(identity == "swift-perception" and version == "2.0.12" for identity, _, version in expected)
for path in sys.argv[1:]:
    if pins(path) != expected:
        raise SystemExit(f"dependency lock changed: {path}")
print("Dependency pins match committed Package.resolved")

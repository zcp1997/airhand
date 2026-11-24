#!/bin/bash
# G1 host checks. A passing result is not iOS device validation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
mkdir -p ios/build/logs
cargo test --locked -p airhand-proto -p airhand-link -p airhand-mobile -p airhand-server 2>&1 | tee ios/build/logs/rust-core.log
cargo test --locked --manifest-path ios/native/Cargo.toml 2>&1 | tee ios/build/logs/ffi.log
SWIFT_TEST_FLAGS=()
if [ -n "${SWIFT_SDK:-}" ]; then
  SWIFT_TEST_FLAGS+=(--sdk "$SWIFT_SDK")
  printf 'Host test SDK: %s\n' "$SWIFT_SDK"
fi
if [ -n "${SWIFT_SCRATCH_PATH:-}" ]; then
  SWIFT_TEST_FLAGS+=(--scratch-path "$SWIFT_SCRATCH_PATH")
fi
if [ -n "${SWIFT_TEST_PLUGIN_PATH:-}" ]; then
  SWIFT_TEST_FLAGS+=(-Xswiftc -plugin-path -Xswiftc "$SWIFT_TEST_PLUGIN_PATH")
fi
if [ -n "${SWIFT_TEST_FRAMEWORK_PATH:-}" ]; then
  SWIFT_TEST_FLAGS+=(-Xswiftc -F -Xswiftc "$SWIFT_TEST_FRAMEWORK_PATH" -Xlinker -F -Xlinker "$SWIFT_TEST_FRAMEWORK_PATH" -Xlinker -rpath -Xlinker "$SWIFT_TEST_FRAMEWORK_PATH")
fi
swift run --package-path ios --build-system native --force-resolved-versions "${SWIFT_TEST_FLAGS[@]}" AirhandCoreSelfTest 2>&1 | tee ios/build/logs/swift-core.log
# Verify the assertion runner really fails, without skipping or changing a core case.
probe_exit=0
swift run --package-path ios --build-system native --skip-build "${SWIFT_TEST_FLAGS[@]}" AirhandCoreSelfTest --probe-failure > ios/build/logs/selftest-failure-probe.log 2>&1 || probe_exit=$?
test "$probe_exit" -eq 1
grep -q 'Expectation was false' ios/build/logs/selftest-failure-probe.log
python3 -m unittest discover -s ios/scripts/tests -v 2>&1 | tee ios/build/logs/ipa-validator-tests.log
for script in ios/scripts/*.sh; do bash -n "$script"; done
"${ACTIONLINT:-actionlint}" .github/workflows/ios16.yml
(cd ios && scripts/prepare-project.sh)
python3 - <<'PY'
from pathlib import Path
project = Path('ios/Airhand.xcodeproj/project.pbxproj').read_text()
targets = [line.strip() for line in project.splitlines() if 'IPHONEOS_DEPLOYMENT_TARGET =' in line]
# XcodeGen puts both deployment settings at project level; all three native targets inherit them.
assert len(targets) >= 2, targets
for target in ['Airhand', 'AirhandBroadcast', 'AirhandTests']:
    assert f'name = {target};' in project, target
assert all('= 16.6;' in line for line in targets), targets
assert 'IPHONEOS_DEPLOYMENT_TARGET=16.6' in Path('ios/scripts/build-rust.sh').read_text()
for source in Path('ios/Airhand').rglob('*.swift'):
    text = source.read_text()
    assert 'import Observation' not in text and '@Observable' not in text and '@Bindable' not in text, source
assert 'cargo build --locked' in Path('ios/scripts/build-rust.sh').read_text()
# Xcode must link the already pinned transitive product explicitly too.
import json
import subprocess
objects = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', 'ios/Airhand.xcodeproj/project.pbxproj']))['objects']
for target in objects.values():
    if target.get('isa') != 'PBXNativeTarget':
        continue
    products = {objects[ref]['productName'] for ref in target.get('packageProductDependencies', [])}
    linked = {objects[objects[ref]['productRef']]['productName'] for phase in target['buildPhases']
              if objects[phase].get('isa') == 'PBXFrameworksBuildPhase' for ref in objects[phase]['files']
              if 'productRef' in objects[ref]}
    expected = {'Perception', 'IssueReporting'} if target['name'] in {'Airhand', 'AirhandTests'} else set()
    assert products == linked == expected, (target['name'], products, linked)
print('Main/Tests explicitly link Perception and IssueReporting; Broadcast has no Swift packages')
print('Generated App/Broadcast/Tests deployment targets: 16.6; Rust: 16.6')
PY
python3 ios/scripts/check-package-lock.py ios/Airhand.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git diff --check
python3 ios/scripts/check-source-safety.py
printf '%s\n' 'G1 automated checks PASS; independent QA still required; G2/G3 NOT RUN.'

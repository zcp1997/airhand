#!/bin/bash
# Generate the project and seed Xcode with the same immutable pins as host tests.
set -euo pipefail
cd "$(dirname "$0")/.."
XCODEGEN="${XCODEGEN:-$(command -v xcodegen)}"
"$XCODEGEN" --version
"$XCODEGEN" generate
lock=Airhand.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
mkdir -p "$(dirname "$lock")"
cp Package.resolved "$lock"

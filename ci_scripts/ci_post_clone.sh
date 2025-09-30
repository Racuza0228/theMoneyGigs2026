#!/bin/bash
set -e

# --- ZZZ_CI_SCRIPT_EXECUTING_FINAL_ATTEMPT_ZZZ ---
# This line is a tracer to confirm script execution in logs.

FLUTTER_BUILD_ARGS="--config-only --no-codesign"

echo "--- CI Script Start: Generating Dependencies ---"

# 1. Navigate to the repo root
cd "$CI_PRIMARY_REPOSITORY_PATH"

# 2. Get Flutter packages
echo "Running flutter pub get..."
flutter pub get

# 3. Generate Flutter iOS configuration files (e.g., Generated.xcconfig)
echo "Running flutter build ios $FLUTTER_BUILD_ARGS"
flutter build ios $FLUTTER_BUILD_ARGS

# 4. Navigate to the iOS folder
cd ios

# 5. Install CocoaPods (Generates Pods-Runner.xcconfig and .xcfilelist files)
echo "Running pod install..."
pod install

echo "--- CI Script Finish: Dependencies Generated Successfully ---"

exit 0
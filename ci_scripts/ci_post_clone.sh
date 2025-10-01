#!/bin/bash
set -e

# --- FIX: Ensure flutter command is found by adding it to the PATH ---
# CI_PRIMARY_REPOSITORY_PATH contains the path to your cloned Git repo.
# This assumes the Flutter SDK is available in the environment path or a known location.
# If using a global Flutter setup, the path might be different, but this is the most common fix.
export PATH="$PATH:/Users/Shared/Library/flutter/bin"
export PATH="$PATH:/Users/Shared/Library/flutter/.pub-cache/bin"
# If the path above fails, try adding the SDK path that Xcode Cloud sets:
# export PATH="$PATH:$FLUTTER_ROOT/bin"
# -------------------------------------------------------------------

# NOTE: The variable $GOOGLE_API_KEY is available from Xcode Cloud secrets.
FLUTTER_API_DEFINE="--dart-define=GOOGLE_API_KEY=$GOOGLE_API_KEY"
FLUTTER_BUILD_ARGS="--config-only --no-codesign $FLUTTER_API_DEFINE"

echo "--- CI Script Start: Generating Dependencies ---"

# 1. Navigate to the repo root
# NOTE: The log shows your script is running from /Volumes/workspace/repository/ios/ci_scripts,
# so we need to navigate up two levels to get to the root.
cd "$CI_PRIMARY_REPOSITORY_PATH"

# 2. Get Flutter packages
echo "Running flutter pub get..."
flutter pub get

# 3. Generate Flutter iOS configuration files for Release/Archive
echo "Running flutter build ipa $FLUTTER_BUILD_ARGS"
flutter build ipa $FLUTTER_BUILD_ARGS

# 4. Navigate to the iOS folder
cd ios

# 5. Install CocoaPods
echo "Running pod install..."
pod install

echo "--- CI Script Finish: Dependencies Generated Successfully ---"

exit 0

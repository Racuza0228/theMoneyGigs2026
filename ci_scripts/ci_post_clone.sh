#!/bin/bash
set -e

echo "--- CI Script Start: Generating Dependencies ---"

# --- FIX: Attempt to set FLUTTER_ROOT and add Flutter to PATH ---
# 1. Standard CI location for Flutter on macOS environments
export PATH="$PATH:/Users/Shared/Library/flutter/bin"

# 2. Add pub cache to path for any required executables
export PATH="$PATH:$HOME/.pub-cache/bin"

# 3. Navigate to the correct repository root before running flutter
# The script runs from /Volumes/workspace/repository/ios/ci_scripts, so navigate to root.
cd "$CI_PRIMARY_REPOSITORY_PATH"

# -------------------------------------------------------------------

# NOTE: The variable $GOOGLE_API_KEY is available from Xcode Cloud secrets.
FLUTTER_API_DEFINE="--dart-define=GOOGLE_API_KEY=$GOOGLE_API_KEY"
FLUTTER_BUILD_ARGS="--config-only --no-codesign $FLUTTER_API_DEFINE"


# 2. Get Flutter packages
echo "Running flutter pub get..."
flutter pub get # This should now work

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

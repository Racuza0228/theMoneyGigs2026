#!/bin/bash
set -e

echo "--- CI Script Start: Generating Dependencies ---"

# --- FIX: Ensure flutter command is found by adding the standard Flutter and Pub Cache paths to the PATH ---
#
# 1. Add the local user's bin folder which sometimes contains the flutter symlink
export PATH="$PATH:$HOME/.local/bin"

# 2. Add the pub cache location, which is critical for some Flutter tools
export PATH="$PATH:$HOME/.pub-cache/bin"

# 3. Add the common global Flutter installation location if using FVM or a central install
export PATH="$PATH:/Users/Shared/Library/flutter/bin"

# 4. Navigate to the repository root where the pubspec.yaml and ios directories are located.
# The script starts from /Volumes/workspace/repository/ios/ci_scripts,
# so $CI_PRIMARY_REPOSITORY_PATH should take us to the root.
cd "$CI_PRIMARY_REPOSITORY_PATH"

# -------------------------------------------------------------------

# NOTE: The variable $GOOGLE_API_KEY is available from Xcode Cloud secrets.
FLUTTER_API_DEFINE="--dart-define=GOOGLE_API_KEY=$GOOGLE_API_KEY"
FLUTTER_BUILD_ARGS="--config-only --no-codesign $FLUTTER_API_DEFINE"


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

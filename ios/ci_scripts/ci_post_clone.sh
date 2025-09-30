#!/bin/bash
set -e

echo "--- CI Script Start: Generating Dependencies ---"

# Define the API key argument using the Xcode Cloud secret variable
# NOTE: The variable name must exactly match your secret name in Xcode Cloud
FLUTTER_API_DEFINE="--dart-define=GOOGLE_API_KEY=$GOOGLE_API_KEY"

# Define the rest of the build arguments
FLUTTER_BUILD_ARGS="--config-only --no-codesign $FLUTTER_API_DEFINE"

# 1. Navigate to the repo root
cd "$CI_PRIMARY_REPOSITORY_PATH"

# 2. Get Flutter packages
echo "Running flutter pub get..."
flutter pub get

# 3. Generate Flutter iOS configuration files (Crucial for fixing .xcconfig errors)
# This step injects the API Key into the configuration files (DartDefines.xcconfig).
echo "Running flutter build ios $FLUTTER_BUILD_ARGS"
flutter build ios $FLUTTER_BUILD_ARGS

# 4. Navigate to the iOS folder
cd ios

# 5. Install CocoaPods (Crucial for fixing .xcfilelist errors)
echo "Running pod install..."
pod install

echo "--- CI Script Finish: Dependencies Generated Successfully ---"

exit 0

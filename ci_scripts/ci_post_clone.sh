#!/bin/sh

# Exit if any command fails
set -e

# Path to the iOS directory (where the Podfile is located)
# CI_PRIMARY_REPO_PATH is an environment variable provided by Xcode Cloud.
IOS_DIR="$CI_PRIMARY_REPO_PATH/ios" 

# 1. Install Flutter dependencies
echo "Running Flutter build iOS..."
flutter_path=$(which flutter)
"$flutter_path" build ios --no-codesign

# 2. Navigate to the iOS directory
cd "$IOS_DIR"

# 3. Install CocoaPods dependencies
echo "Running pod install..."
pod_path=$(which pod)
"$pod_path" install

exit 0
#!/bin/sh

# Exit if any command fails
set -e

echo "--- Xcode Cloud Post-Clone Script Starting ---"

# 1. Define the iOS directory path
IOS_DIR="$CI_PRIMARY_REPO_PATH/ios" 

# 2. Navigate to the main repo root 
echo "Navigating to: $CI_PRIMARY_REPO_PATH"
cd "$CI_PRIMARY_REPO_PATH"

# 3. Ensure Flutter dependencies are ready and the Flutter configuration file is generated
echo "Running Flutter build iOS..."
flutter build ios --no-codesign

# 4. Navigate to the iOS directory where the Podfile is located
echo "Navigating to Podfile directory: $IOS_DIR"
cd "$IOS_DIR"

# 5. Check if Podfile exists (Diagnostic)
if [ ! -f "Podfile" ]; then
    echo "ERROR: Podfile not found in $IOS_DIR. Build cannot continue."
    exit 1
fi

# 6. Install CocoaPods dependencies and generate missing files
echo "Running pod install..."
pod install

echo "--- Xcode Cloud Post-Clone Script Finished Successfully ---"

exit 0
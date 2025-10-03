#!/bin/sh

set -e

# Navigate to repository root
cd $CI_PRIMARY_REPOSITORY_PATH

# Install Flutter using git
git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter
export PATH="$HOME/flutter/bin:$PATH"

# Configure Flutter
flutter precache --ios

# Get dependencies
flutter pub get

# Run Flutter build to generate necessary files
flutter build ios --release --no-codesign

# Install CocoaPods
cd ios
pod install

echo "Flutter setup complete"
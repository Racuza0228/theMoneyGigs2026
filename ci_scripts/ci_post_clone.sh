#!/bin/sh

# Fail if any command fails
set -e

echo "🧩 Stage: Post-clone is activated..."

# Install Flutter using Homebrew
# This assumes Homebrew is available in the Xcode Cloud environment
brew install --cask flutter

# Add Flutter to the PATH
export PATH="$HOME/flutter/bin:$PATH"

# Enable macOS desktop support if needed (adjust based on your project)
# flutter config --enable-macos-desktop

# Run Flutter doctor to check for setup issues
flutter doctor

# Get Flutter packages
flutter pub get

# If you use build_runner for code generation (e.g., Freezed, Riverpod)
# flutter pub run build_runner build

# Install CocoaPods dependencies for the iOS project
# Navigate to the iOS directory first
cd ios
pod install

echo "🎯 Stage: Post-clone is done."

exit 0

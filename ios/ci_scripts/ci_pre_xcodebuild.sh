#!/bin/sh

set -e

# Navigate to repository root
cd $CI_PRIMARY_REPOSITORY_PATH

# Check if Flutter is already installed, if not install it
if [ ! -d "$HOME/flutter" ]; then
    echo "Installing Flutter..."
    git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter
else
    echo "Flutter already installed"
fi

export PATH="$HOME/flutter/bin:$PATH"

# Verify Flutter installation
flutter --version

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

#!/bin/sh
set -e
# Final fix attempt: Forced push update
echo "========================================="
echo "🚀 Xcode Cloud Post-Clone Script"
echo "========================================="

# Environment info
echo "📍 Repository Path: $CI_PRIMARY_REPO_PATH"
echo "📍 Workspace: $CI_WORKSPACE"
echo "📍 Current Directory: $(pwd)"

# Navigate to repo root
cd "$CI_PRIMARY_REPO_PATH"

# Flutter setup
echo ""
echo "📦 Flutter Setup"
echo "----------------"
flutter --version
flutter doctor -v

# Clean and get dependencies
echo ""
echo "🧹 Cleaning Flutter project..."
flutter clean

echo ""
echo "📥 Getting Flutter packages..."
flutter pub get

# Generate iOS configuration files
echo ""
echo "⚙️  Generating Flutter iOS configuration..."
flutter build ios --config-only --no-codesign

# Verify Generated.xcconfig was created
if [ ! -f "ios/Flutter/Generated.xcconfig" ]; then
    echo "❌ ERROR: Generated.xcconfig not created!"
    echo "Listing ios/Flutter directory:"
    ls -la ios/Flutter/
    exit 1
fi

echo "✅ Generated.xcconfig created successfully"

# CocoaPods setup
echo ""
echo "🔧 CocoaPods Setup"
echo "------------------"
cd ios

# Verify Podfile
if [ ! -f "Podfile" ]; then
    echo "❌ ERROR: Podfile not found in ios directory!"
    ls -la
    exit 1
fi

echo "📝 Podfile found"

# Deintegrate old pods if any (cleanup)
echo "🧹 Cleaning old pods..."
pod deintegrate || true
rm -rf Pods
rm -rf Podfile.lock

# Install pods
echo ""
echo "📦 Installing CocoaPods dependencies..."
pod install --repo-update

# Verify workspace was created
if [ ! -f "Runner.xcworkspace" ]; then
    echo "❌ ERROR: Runner.xcworkspace not created!"
    ls -la
    exit 1
fi

echo ""
echo "✅ Runner.xcworkspace created successfully"

# Verify critical files exist
echo ""
echo "🔍 Verifying generated files..."
REQUIRED_FILES=(
    "Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig"
    "Pods/Target Support Files/Pods-Runner/Pods-Runner-frameworks-Release-input-files.xcfilelist"
    "Pods/Target Support Files/Pods-Runner/Pods-Runner-frameworks-Release-output-files.xcfilelist"
    "Flutter/Generated.xcconfig"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file"
    else
        echo "❌ MISSING: $file"
    fi
done

echo ""
echo "========================================="
echo "✨ Post-Clone Script Completed"
echo "========================================="
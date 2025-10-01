#!/bin/bash
set -e

echo "--- CI Script Start: Environment Diagnostics ---"

# 1. Print the current PATH to see where the system is looking
echo "CURRENT PATH: $PATH"

# 2. Find every 'flutter' executable on the entire system (slow but definitive)
echo "SEARCHING FOR FLUTTER EXECUTABLE (this may take a minute)..."
find / -type f -name 'flutter' 2>/dev/null | grep -v "Library/Application Support"
# The 'grep' is to filter out irrelevant application support files.

# 3. Print the system's home directory (in case flutter is in a user path)
echo "HOME DIR: $HOME"

echo "--- CI Script Finish: Diagnostics Complete ---"

exit 0
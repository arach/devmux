#!/bin/bash
set -euo pipefail

# Build universal binary and prep for GitHub release
cd "$(dirname "$0")/../app"

echo "Building universal binary..."
swift build -c release --arch arm64 --arch x86_64

BINARY=".build/apple/Products/Release/DevmuxApp"
DEST="../dist/DevmuxApp-macos-universal"

mkdir -p ../dist
cp "$BINARY" "$DEST"
chmod +x "$DEST"

echo ""
echo "Binary: $DEST"
ls -lh "$DEST"
file "$DEST"
echo ""
echo "To create a release:"
echo "  gh release create v\$(node -p \"require('../package.json').version\") $DEST --title \"v\$(node -p \"require('../package.json').version\")\""

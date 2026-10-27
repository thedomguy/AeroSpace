#!/bin/bash
# Build this fork, sign it with the personal Apple Development identity and install it
# over /Applications/AeroSpace.app + ~/.local/bin/aerospace. Not managed by Homebrew.
# Keeps bundle ID bobko.aerospace so the Accessibility grant survives rebuilds.
set -euo pipefail
cd "$(dirname "$0")"

identity="Apple Development: rbhatt800@icloud.com (3VT62USP87)"
version="$(git describe --tags --abbrev=0)-$(git rev-parse --abbrev-ref HEAD)"
cli_dest="$HOME/.local/bin/aerospace"

./generate.sh --build-version "$version" --codesign-identity "$identity" --generate-git-hash > /dev/null
xcrun xcodebuild build -scheme AeroSpace -destination "generic/platform=macOS" -configuration Release \
    -derivedDataPath .xcode-build > .xcode-build.log 2>&1 || { grep -E "error:" .xcode-build.log; exit 1; }
swift build -c release --arch arm64 --product aerospace > /dev/null
git checkout -q -- AeroSpace.xcodeproj Sources/Common/gitHashGenerated.swift Sources/Common/versionGenerated.swift 2> /dev/null || true

killall AeroSpace 2> /dev/null || true
while pgrep -x AeroSpace > /dev/null; do sleep 0.2; done
rm -rf /Applications/AeroSpace.app
cp -R .xcode-build/Build/Products/Release/AeroSpace.app /Applications/
mkdir -p "$(dirname "$cli_dest")"
cp .build/arm64-apple-macosx/release/aerospace "$cli_dest"
codesign --force --sign "$identity" "$cli_dest" 2> /dev/null
open -a /Applications/AeroSpace.app
for _ in $(seq 20); do "$cli_dest" list-workspaces --focused > /dev/null 2>&1 && break; sleep 0.5; done
"$cli_dest" --version

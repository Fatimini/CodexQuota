#!/bin/bash
# Build an isolated, ad-hoc signed Apple Silicon trial archive. Never replace old apps.
set -euo pipefail
cd "$(dirname "$0")"
version=$(tr -d '[:space:]' < VERSION)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid VERSION' >&2; exit 1; }
[[ "$(uname -m)" == arm64 ]] || { echo 'Build this trial on Apple Silicon.' >&2; exit 1; }
swift build -c release
mkdir -p releases
destination=$(mktemp -d "$(pwd)/releases/v${version}-trial.XXXXXX")
folder="CodexQuota-v${version}-macOS-arm64"
bundle="$destination/$folder/CodexQuota.app"
mkdir -p "$bundle/Contents/MacOS"
cp .build/release/CodexQuota "$bundle/Contents/MacOS/"
cp Info.plist "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$bundle/Contents/Info.plist"
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
cp INSTALL.md "$destination/$folder/INSTALL.md"
cp LICENSE "$destination/$folder/LICENSE"
archive="$folder.zip"
ditto -c -k --norsrc --keepParent "$destination/$folder" "$destination/$archive"
(cd "$destination" && shasum -a 256 "$archive" > SHA256SUMS.txt)
echo "$destination/$archive"

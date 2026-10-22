#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64 --arch x86_64
app=limitbar.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/limitbar "$app/Contents/MacOS/"
cp Sources/limitbar/Resources/Info.plist "$app/Contents/"
cp Assets/AppIcon.icns "$app/Contents/Resources/"
cp -R .build/release/limitbar_limitbar.bundle "$app/Contents/Resources/"
identity="limitbar Local Signing"
security find-identity -p codesigning | grep -q "\"$identity\"" || identity=-
codesign --force --deep --sign "$identity" "$app"
echo "built $app (signed with $identity)"

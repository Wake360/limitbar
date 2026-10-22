#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/bundle.sh
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" limitbar.app/Contents/Info.plist)
stage=$(mktemp -d)
ditto limitbar.app "$stage/limitbar.app"
ln -s /Applications "$stage/Applications"
mkdir -p dist
dmg=dist/limitbar-$version.dmg
hdiutil create -volname limitbar -srcfolder "$stage" -format UDZO -ov "$dmg" >/dev/null
rm -rf "$stage"
(cd dist && shasum -a 256 "limitbar-$version.dmg" > "limitbar-$version.dmg.sha256")
echo "built $dmg"

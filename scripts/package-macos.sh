#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$project_dir/build}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

stage="$(mktemp -d "${TMPDIR:-/tmp}/nothing-x-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app_dir="$stage/disk"
mkdir -p "$app_dir"

xcodebuild -project "$project_dir/Nothing X MacOS.xcodeproj" -scheme 'Nothing X MacOS' \
  -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$stage/DerivedData" \
  CODE_SIGNING_ALLOWED=NO 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build

app="$app_dir/Nothing X.app"
ditto --norsrc "$stage/DerivedData/Build/Products/Release/Nothing X.app" "$app"
xattr -cr "$app"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
architectures="$(lipo -archs "$app/Contents/MacOS/Nothing X")"
for architecture in arm64 x86_64; do
  case " $architectures " in
    *" $architecture "*) ;;
    *) printf 'Missing required app architecture %s\n' "$architecture" >&2; exit 1 ;;
  esac
done
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"

ln -s /Applications "$app_dir/Applications"
name="Nothing-X-Mac-$version-universal.dmg"
hdiutil create -volname 'Nothing X for Mac' -srcfolder "$app_dir" -fs HFS+ -format UDZO "$stage/$name"
hdiutil verify "$stage/$name"
mv "$stage/$name" "$output_dir/$name"
printf '%s\n' "$output_dir/$name"

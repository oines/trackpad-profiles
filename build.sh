#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
arch="$(uname -m)"
app="build/Trackpad Profiles.app"

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

xcrun --sdk macosx clang \
    -std=c17 -O2 -Wall -Wextra -Werror \
    -arch "$arch" -mmacosx-version-min=14.0 \
    -c Sources/TouchBridge.c -o "build/TouchBridge-$arch.o"

xcrun --sdk macosx swiftc \
    -swift-version 5 -O -target "$arch-apple-macosx14.0" \
    -import-objc-header Sources/TouchBridge.h \
    Sources/*.swift "build/TouchBridge-$arch.o" \
    -o "$app/Contents/MacOS/TrackpadProfiles"

cp Info.plist "$app/Contents/Info.plist"
cp LICENSE.txt "$app/Contents/Resources/LICENSE.txt"
codesign --force --sign - "$app"
codesign --verify --strict "$app"

printf '%s\n' "$PWD/$app"

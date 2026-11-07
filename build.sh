#!/bin/bash
# Compila DAW Sync como app universal (Apple Silicon + Intel). Requiere macOS con Xcode o Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/DAW Sync.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for ARCH in arm64 x86_64; do
  echo "Compilando ${ARCH}..."
  xcrun swiftc -O -swift-version 5 -parse-as-library \
    -target "$ARCH-apple-macos13.0" -sdk "$SDK" \
    Sources/*.swift -o "build/DAWSync-$ARCH"
done

lipo -create -output "$APP/Contents/MacOS/DAWSync" build/DAWSync-arm64 build/DAWSync-x86_64
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Firma ad-hoc (sin cuenta de Apple Developer)
codesign --force --deep --sign - "$APP"

(cd build && ditto -c -k --keepParent "DAW Sync.app" DAWSync-macOS.zip)
echo "Listo: build/DAWSync-macOS.zip"

#!/bin/bash
# Builds dist/SoeYaku.app with a fixed signature, so that the screen recording permission stays attached to the app across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."
identity=${SIGN_IDENTITY:-}
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning | awk '/"Apple Development:/ && !found { print $2; found=1 }')
fi
if [[ -z "$identity" || "$identity" == "-" ]]; then
  echo "固定署名が必要です。キーチェーンに Apple Development 証明書を用意するか SIGN_IDENTITY を指定してください。" >&2
  exit 1
fi
swift build -c release --product SoeYaku
bin=$(swift build -c release --show-bin-path)
mkdir -p dist
stage=$(mktemp -d "$PWD/dist/build.XXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/SoeYaku.app"
mkdir -p "$app/Contents/"{MacOS,Resources,Helpers}
cp App/Info.plist "$app/Contents/"
cp "$bin/SoeYaku" "$app/Contents/MacOS/"
swiftc -O -target "$(uname -m)-apple-macosx26.0" Scripts/start-model.swift -o "$app/Contents/Helpers/start-model"
codesign --force --sign "$identity" --timestamp=none "$app/Contents/Helpers/start-model"
codesign --force --sign "$identity" --timestamp=none "$app"
codesign --verify --deep --strict "$app"
if [[ -d dist/SoeYaku.app ]]; then mv dist/SoeYaku.app "$stage/previous.app"; fi
if ! mv "$app" dist/SoeYaku.app; then
  if [[ -d "$stage/previous.app" ]]; then mv "$stage/previous.app" dist/SoeYaku.app; fi
  exit 1
fi
echo "dist/SoeYaku.app"

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./tools/build-app.sh
version=$(cat VERSION)
architecture=${CAFFEINATOR_ARCH:-arm64}
case "$architecture" in arm64) suffix=aarch64 ;; x86_64) suffix=x64 ;; *) echo "Unsupported architecture" >&2; exit 1 ;; esac
stage=$(mktemp -d /tmp/caffeinator-dmg.XXXXXX)
trap 'rm -rf "$stage"' EXIT
cp -R dist/Caffeinator.app "$stage/"
ln -s /Applications "$stage/Applications"
dmg="dist/Caffeinator_v${version}_${suffix}.dmg"
hdiutil create -volname Caffeinator -srcfolder "$stage" -ov -format UDZO "$dmg"
hdiutil verify "$dmg"
shasum -a 256 "$dmg"

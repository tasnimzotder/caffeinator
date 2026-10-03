#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(cat VERSION)
configuration=${CAFFEINATOR_BUILD_CONFIGURATION:-release}
architecture=${CAFFEINATOR_ARCH:-arm64}
swift build -c "$configuration" --arch "$architecture" -Xswiftc -warnings-as-errors
binary_dir=$(swift build -c "$configuration" --arch "$architecture" --show-bin-path)
app="dist/Caffeinator.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/caffeinator" "$app/Contents/MacOS/caffeinator"
cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>caffeinator</string>
<key>CFBundleIdentifier</key><string>com.tasnimzotder.caffeinator</string>
<key>CFBundleName</key><string>Caffeinator</string>
<key>CFBundleDisplayName</key><string>Caffeinator</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>${version%%-*}</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
echo "Built $app ($version, $architecture)"

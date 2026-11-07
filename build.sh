#!/bin/zsh
# 编译 MacSweep 并打包成 .app（无需 Xcode 工程，只需 Xcode 命令行工具）
#   ./build.sh            构建当前架构
#   ./build.sh universal  构建 Apple Silicon + Intel 通用版本，并打包 zip
set -euo pipefail
cd "$(dirname "$0")"

APP=build/MacSweep.app
VERSION=$(sed -n 's/^let appVersion = "\(.*\)"/\1/p' Sources/Engine.swift)
FLAGS=(-O -swift-version 5 -parse-as-library)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "${1:-}" == "universal" ]]; then
  for arch in arm64 x86_64; do
    swiftc "${FLAGS[@]}" -target "$arch-apple-macos13.0" Sources/*.swift -o "build/MacSweep-$arch"
  done
  lipo -create build/MacSweep-arm64 build/MacSweep-x86_64 -output "$APP/Contents/MacOS/MacSweep"
  rm build/MacSweep-arm64 build/MacSweep-x86_64
else
  swiftc "${FLAGS[@]}" Sources/*.swift -o "$APP/Contents/MacOS/MacSweep"
fi

[[ -f Resources/AppIcon.icns ]] || swift scripts/make_icon.swift Resources/AppIcon.icns
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>MacSweep</string>
  <key>CFBundleDisplayName</key><string>MacSweep</string>
  <key>CFBundleIdentifier</key><string>io.github.macsweep</string>
  <key>CFBundleExecutable</key><string>MacSweep</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true

if [[ "${1:-}" == "universal" ]]; then
  ditto -c -k --keepParent "$APP" "build/MacSweep-$VERSION.zip"
  echo "📦 build/MacSweep-$VERSION.zip"
fi
echo "✅ $APP  v$VERSION  ($(du -sh "$APP" | cut -f1), $(lipo -archs "$APP/Contents/MacOS/MacSweep"))"

#!/bin/zsh
# 一键构建 WakeDisplay.app 并安装到 /Applications
# Build WakeDisplay.app and install it to /Applications
# 前置 / Requires: xcode-select --install（Xcode Command Line Tools）
set -e
cd "$(dirname "$0")"

VERSION="1.29"
APP=WakeDisplay.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # 7 KB, pre-optimised (see tools/icon)

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>WakeDisplay</string>
  <key>CFBundleDisplayName</key><string>WakeDisplay</string>
  <key>CFBundleIdentifier</key><string>com.jason.wakedisplay</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>WakeDisplay</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>com.jason.wakedisplay</string>
    <key>CFBundleURLSchemes</key><array><string>wakedisplay</string></array>
  </dict></array>
</dict></plist>
EOF

echo "▶ 编译主程序 / Building app…"
# -Osize: optimise for size · -dead_strip: drop unused code · strip -x: drop local symbols
swiftc -Osize -wmo -enforce-exclusivity=unchecked -import-objc-header CGVirtualDisplay.h main.swift Localization.swift Telemetry.swift Updater.swift Advanced.swift Extras.swift AutoOutdoor.swift -o "$APP/Contents/MacOS/WakeDisplay" \
  -Xlinker -dead_strip -Xlinker -dead_strip_dylibs -framework Cocoa -framework Carbon -framework IOKit -framework Metal -framework QuartzCore
strip -x "$APP/Contents/MacOS/WakeDisplay"

codesign --force --sign - "$APP"   # ad-hoc 签名 / ad-hoc signature

# CI sets SKIP_INSTALL=1 to only build the .app
if [ -n "$SKIP_INSTALL" ]; then echo "✅ Built $APP $VERSION"; exit 0; fi

echo "▶ 安装到 /Applications"
rm -rf "/Applications/$APP"
cp -R "$APP" /Applications/
# Register the app (wakedisplay:// URL scheme) with the system
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP" || true

echo "✅ 完成 / Done ($VERSION)。启动 / Launch:"
echo "   open /Applications/$APP"

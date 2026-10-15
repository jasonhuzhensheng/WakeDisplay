#!/bin/zsh
# 一键构建 WakeDisplay.app（含桌面小组件）并安装到 /Applications
# Build WakeDisplay.app (with its desktop widget) and install it to /Applications
# 前置 / Requires: xcode-select --install（Xcode Command Line Tools）
set -e
cd "$(dirname "$0")"

VERSION="1.17.2"
APP=WakeDisplay.app
WIDGET="$APP/Contents/PlugIns/WakeDisplayWidget.appex"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

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
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>com.jason.wakedisplay</string>
    <key>CFBundleURLSchemes</key><array><string>wakedisplay</string></array>
  </dict></array>
</dict></plist>
EOF

echo "▶ 编译主程序 / Building app…"
swiftc -O -import-objc-header CGVirtualDisplay.h main.swift Localization.swift Telemetry.swift Updater.swift Advanced.swift Extras.swift AutoOutdoor.swift -o "$APP/Contents/MacOS/WakeDisplay" \
  -framework Cocoa -framework Carbon -framework IOKit -framework Metal -framework QuartzCore

# Widget needs macOS 14 (WidgetKit on macOS + containerBackground). Skip quietly on older SDKs.
OSMAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$OSMAJOR" -ge 14 ]; then
  echo "▶ 编译小组件 / Building widget…"
  mkdir -p "$WIDGET/Contents/MacOS"
  sed "s/__VERSION__/$VERSION/g" Widget/Info.plist > "$WIDGET/Contents/Info.plist"
  swiftc -O -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    Widget/WakeDisplayWidget.swift -o "$WIDGET/Contents/MacOS/WakeDisplayWidget" \
    -framework WidgetKit -framework SwiftUI
  codesign --force --sign - --entitlements Widget/Widget.entitlements "$WIDGET"
else
  echo "ℹ︎ macOS < 14: 跳过小组件 / skipping widget"
fi

codesign --force --sign - "$APP"   # ad-hoc 签名 / ad-hoc signature

# CI sets SKIP_INSTALL=1 to only build the .app
if [ -n "$SKIP_INSTALL" ]; then echo "✅ Built $APP $VERSION"; exit 0; fi

echo "▶ 安装到 /Applications"
rm -rf "/Applications/$APP"
cp -R "$APP" /Applications/
# Register the app (URL scheme) and its widget with the system
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP" || true
[ -d "/Applications/$WIDGET" ] && pluginkit -a "/Applications/$WIDGET" || true

echo "✅ 完成 / Done ($VERSION)。启动 / Launch:"
echo "   open /Applications/$APP"
echo "   小组件 / Widget: 右键桌面 →「编辑小组件」→ 搜索 WakeDisplay"

#!/bin/zsh
# 一键构建 WakeDisplay.app 并安装到 /Applications
# 前置：xcode-select --install（Xcode Command Line Tools）
set -e
cd "$(dirname "$0")"

APP=WakeDisplay.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>WakeDisplay</string>
  <key>CFBundleDisplayName</key><string>WakeDisplay</string>
  <key>CFBundleIdentifier</key><string>com.jason.wakedisplay</string>
  <key>CFBundleVersion</key><string>1.7</string>
  <key>CFBundleShortVersionString</key><string>1.7</string>
  <key>CFBundleExecutable</key><string>WakeDisplay</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

echo "▶ 编译中…"
swiftc -O -import-objc-header CGVirtualDisplay.h main.swift -o "$APP/Contents/MacOS/WakeDisplay" \
  -framework Cocoa -framework Carbon -framework IOKit -framework Metal -framework QuartzCore

codesign --force --deep --sign - "$APP"   # ad-hoc 签名，避免 Gatekeeper 阻止

# CI sets SKIP_INSTALL=1 to only build the .app
if [ -n "$SKIP_INSTALL" ]; then echo "✅ Built $APP"; exit 0; fi

echo "▶ 安装到 /Applications"
rm -rf "/Applications/$APP"
cp -R "$APP" /Applications/

echo "✅ 完成。启动："
echo "   open /Applications/$APP"
echo "   （右键状态栏图标 → 勾选「开机自动启动」）"

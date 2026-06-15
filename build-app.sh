#!/bin/bash
# 构建 ClaudeMeter 并打包成带 LSUIElement（纯菜单栏、无 Dock 图标）的 .app
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClaudeMeter"
CONFIG="release"
BUILD_DIR=".build/${CONFIG}"
APP_BUNDLE="${APP_NAME}.app"

echo "==> 编译（${CONFIG}）"
swift build -c "${CONFIG}"

echo "==> 组装 ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# 从 Assets/AppIcon.png 生成 .icns 并放入 Resources
ICON_SRC="Assets/AppIcon.png"
if [ -f "${ICON_SRC}" ]; then
    echo "==> 生成应用图标"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "${ICONSET}"
    for size in 16 32 64 128 256 512; do
        sips -z "${size}" "${size}"       "${ICON_SRC}" --out "${ICONSET}/icon_${size}x${size}.png"   >/dev/null
        sips -z "$((size*2))" "$((size*2))" "${ICON_SRC}" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "${ICONSET}" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "${ICONSET}")"
fi

cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> 本地签名（ad-hoc）"
codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || echo "   跳过签名（不影响本机运行）"

echo "==> 完成：${PWD}/${APP_BUNDLE}"
echo "   运行： open ${APP_BUNDLE}"
echo "   安装： cp -r ${APP_BUNDLE} /Applications/"

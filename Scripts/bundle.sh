#!/bin/bash
# 把 swift build 产物组装成 NotchIsland.app（菜单栏 App）。
# 用法: Scripts/bundle.sh [debug|release]  默认 debug
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG"
BIN=".build/$CONFIG/NotchIslandApp"

APP="build/NotchIsland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/NotchIslandApp"
# 采集脚本随包附带（安装时拷到 ~/.notchisland）
cp Scripts/claude-statusline.py "$APP/Contents/Resources/claude-statusline.py" 2>/dev/null || true

echo "已打包: $APP"

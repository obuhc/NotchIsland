#!/bin/bash
# 正式安装 NotchIsland：release 构建 → 装到 /Applications → 安装采集器。
set -euo pipefail
cd "$(dirname "$0")/.."

bash Scripts/bundle.sh release

# statusLine 采集器
mkdir -p "$HOME/.notchisland"
cp Scripts/claude-statusline.py "$HOME/.notchisland/claude-statusline.py"
chmod +x "$HOME/.notchisland/claude-statusline.py"

# App 装到 /Applications（开机启动 SMAppService 在此路径最可靠）
rm -rf /Applications/NotchIsland.app
cp -R build/NotchIsland.app /Applications/NotchIsland.app

echo "✅ 已安装 /Applications/NotchIsland.app"
echo "   启动: open /Applications/NotchIsland.app"
echo "   提示: Claude 官方用量默认关闭。右击灵动岛 → 设置 → 开启「启用官方用量」并授权后生效。"

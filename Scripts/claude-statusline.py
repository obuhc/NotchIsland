#!/usr/bin/env python3
"""NotchIsland · Claude statusLine 采集器

被 Claude Code 当作 statusLine 命令调用：每次渲染从 stdin 收到会话 JSON，
其中 `rate_limits`（订阅用户首次 API 响应后出现）含官方 5h / 7d 限额。
本脚本把它落盘到 ~/.notchisland/claude-usage.json 供灵动岛读取，
同时在底部状态栏渲染一行简洁用量，顺便给用户增益。

rate_limits 结构（与 Codex 对齐）：
  five_hour / seven_day → { used_percentage: 0-100, resets_at: unix秒 }
"""
import sys, json, os, time

raw = sys.stdin.read()
try:
    d = json.loads(raw) if raw.strip() else {}
except Exception:
    d = {}

rl = d.get("rate_limits") or {}
model = (d.get("model") or {}).get("display_name") or "Claude"

# 落盘（仅当官方数据存在时覆盖，避免用空数据冲掉上次有效值）
if rl:
    home = os.path.expanduser("~/.notchisland")
    try:
        os.makedirs(home, exist_ok=True)
        payload = {"rate_limits": rl, "capturedAt": time.time(), "model": model}
        tmp = os.path.join(home, "claude-usage.json.tmp")
        with open(tmp, "w") as f:
            json.dump(payload, f)
        os.replace(tmp, os.path.join(home, "claude-usage.json"))
    except Exception:
        pass  # 落盘失败不能影响状态栏渲染

# 渲染状态栏
parts = [model]
fh = (rl.get("five_hour") or {}).get("used_percentage")
sd = (rl.get("seven_day") or {}).get("used_percentage")
if fh is not None:
    parts.append(f"5h {fh:.0f}%")
if sd is not None:
    parts.append(f"7d {sd:.0f}%")
sys.stdout.write("  ·  ".join(parts))

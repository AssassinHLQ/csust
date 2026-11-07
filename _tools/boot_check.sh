#!/usr/bin/env bash
# 启动冒烟：headless 跑一遍游戏，把报错和几行关键日志捞出来。
#
#   _tools/boot_check.sh            # 跑 900 帧，只打「报错 + 新区域日志」
#   _tools/boot_check.sh 1800       # 帧数自己给
#
# ⚠️ 判据只看 `SCRIPT ERROR` / `Parse Error` / `push_error` 打出来的行；
#    `push_warning` 那类是刻意的（例如没放本地音频），不要当成失败。
set -u
GODOT="/d/SOFTWARE/Godot-4.7.1-dotnet/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64_console.exe"
export APPDATA='C:\Users\WY157\Desktop\GODOT\_godot_editor_data\Roaming'
export LOCALAPPDATA='C:\Users\WY157\Desktop\GODOT\_godot_editor_data\Local'
FRAMES="${1:-900}"
cd "$(dirname "$0")/.." || exit 1
"$GODOT" --path . --headless --quit-after "$FRAMES" -- --splat=off --story=off 2>&1

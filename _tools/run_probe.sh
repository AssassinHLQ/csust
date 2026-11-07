#!/usr/bin/env bash
# 跑一个探针 / 自检（headless）。
#
#   _tools/run_probe.sh res://scripts/_probe_mondrian_spot.gd
#   _tools/run_probe.sh res://scripts/_verify_mondrian.gd -- --splat=off
#
# ⚠️ 两个环境变量必须指到项目里的 _godot_editor_data：
#    否则 headless 启动会用用户真实的 AppData，和编辑器/正式运行**不是同一份**
#    （导入缓存、settings.cfg 全部对不上，栽过一次）。
set -u
GODOT="/d/SOFTWARE/Godot-4.7.1-dotnet/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64_console.exe"
export APPDATA='C:\Users\WY157\Desktop\GODOT\_godot_editor_data\Roaming'
export LOCALAPPDATA='C:\Users\WY157\Desktop\GODOT\_godot_editor_data\Local'
SCRIPT="${1:?用法: run_probe.sh res://scripts/_probe_x.gd [-- 额外参数]}"
shift
cd "$(dirname "$0")/.." || exit 1
"$GODOT" --path . --headless --script "$SCRIPT" "$@"

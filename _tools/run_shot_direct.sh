#!/usr/bin/env bash
# 出图 / 真窗口探针：**不带 `--no-capture`**（真的去动鼠标、真的捕获）。
#
#   _tools/run_shot_direct.sh res://scripts/_probe_x.gd [-- 额外参数]
#
# 和 `run_shot.sh` 的唯一区别：命令行里**没有** `-- --no-capture`。
# `run_shot.sh` 那条带 `--no-capture`（游戏永远不收鼠标，免得抢用户），
# 但「开场 PV 期间鼠标要看得见」这类用例必须让引擎**真去改**鼠标模式，
# 否则等于在闸门关着的时候验闸门。
#
# ⚠️ 窗口仍然在屏幕外（`offscreen_window.gd` 的 `apply()` + 下面 -4000,-4000），
#    跑完自己 quit —— 不会抢用户前台。
set -u
GODOT="/d/SOFTWARE/Godot-4.7.1-dotnet/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64_console.exe"
export APPDATA='C:\Users\WY157\Desktop\GODOT\_godot_editor_data\Roaming'
export LOCALAPPDATA='C:\Users\WY157\Desktop\GODOT\_godot_editor_data\Local'
SCRIPT="${1:?用法: run_shot_direct.sh res://scripts/_probe_x.gd [-- 额外参数]}"
shift
TOOLS="$(cd "$(dirname "$0")" && pwd)"
cd "$TOOLS/.." || exit 1

PS="powershell.exe"
run_godot() {
  "$GODOT" --path . --position -4000,-4000 --resolution 1600x900 --windowed \
    --audio-driver Dummy --script "$SCRIPT" -- "$@"
}

if command -v "$PS" >/dev/null 2>&1; then
  "$PS" -NoProfile -ExecutionPolicy Bypass -File "$TOOLS/_focus.ps1" save >/dev/null 2>&1 || true
  run_godot "$@" &
  GODOT_PID=$!
  sleep 0.7
  "$PS" -NoProfile -ExecutionPolicy Bypass -File "$TOOLS/_focus.ps1" restore >/dev/null 2>&1 || true
  wait "$GODOT_PID"
else
  run_godot "$@"
fi

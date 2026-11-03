#!/usr/bin/env bash
# 跑一个**出图**探针（要真窗口，不能 headless）。
#
#   _tools/run_shot.sh res://scripts/_probe_mondrian_shot.gd
#
# 窗口只用于拿渲染纹理，但放到屏幕外并且不抢焦点，不占用户前台。
#
# ⚠️ 出图必须真窗口：`--headless` 下 `get_texture().get_image()` 拿不到内容
#    （`gdgs` 那一行 "headless environment: rendering backend selection skipped"
#    就是征兆）。窗口在屏幕外跑几秒，跑完自己关。
# ⚠️ `--script` 模式下 game.gd 会跳过抢前台/抢鼠标（见 `_watch_input()`），
#    所以不用担心它把鼠标锁走。
set -u
GODOT="/d/SOFTWARE/Godot-4.7.1-dotnet/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64_console.exe"
export APPDATA='C:\Users\WY157\Desktop\GODOT\_godot_editor_data\Roaming'
export LOCALAPPDATA='C:\Users\WY157\Desktop\GODOT\_godot_editor_data\Local'
SCRIPT="${1:?用法: run_shot.sh res://scripts/_probe_x_shot.gd [-- 额外参数]}"
shift
cd "$(dirname "$0")/.." || exit 1
"$GODOT" --path . --position -4000,-4000 --resolution 1280x720 --windowed --audio-driver Dummy --script "$SCRIPT" "$@"

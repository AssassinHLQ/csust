#!/usr/bin/env bash
# 跑一个**出图**探针（要真窗口，不能 headless）。
#
#   _tools/run_shot.sh res://scripts/_probe_mondrian_shot.gd
#
# 窗口只用于拿渲染纹理，但放到屏幕外并且不抢焦点，**绝不占用户前台**。
#
# ⚠️ 出图必须真窗口：`--headless` 下 `get_texture().get_image()` 拿不到内容
#    （`gdgs` 那一行 "headless environment: rendering backend selection skipped"
#    就是征兆）。窗口在屏幕外跑几秒，跑完自己关。
#
# ⚠️ **绝对不许抢用户前台**（用户 2026-11-09：「你弹窗口测试不要抢占我的前台，
#    你在后台弹窗口测试，不要影响我玩游戏」）。
#
# ⚠️ 下面的 `--position -4000,-4000 --resolution 1280x720 --windowed` **实测无效**！
#    2026-11-09 量过：窗口照样开在 (0, 34)、2560×1334、还抢到焦点。
#    真因是 `project.godot` 里 `window/size/mode=2`（最大化），项目设置先于命令行生效。
#
#    真正管用的是**探针脚本自己在运行时改**：
#        const OffWin := preload("res://scripts/offscreen_window.gd")
#        await OffWin.apply(self)
#    命令行参数留着只是"尽力而为"，别指望它。
#    验证方式：跑 `res://scripts/_probe_no_steal_focus.gd`，会直接打印窗口位置与断言。
#
#    `-- --no-capture` 仍然有效：让 `player.gd::_may_capture()` 永远不收鼠标。
set -u
GODOT="/d/SOFTWARE/Godot-4.7.1-dotnet/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64_console.exe"
export APPDATA='C:\Users\WY157\Desktop\GODOT\_godot_editor_data\Roaming'
export LOCALAPPDATA='C:\Users\WY157\Desktop\GODOT\_godot_editor_data\Local'
SCRIPT="${1:?用法: run_shot.sh res://scripts/_probe_x_shot.gd [-- 额外参数]}"
shift
TOOLS="$(cd "$(dirname "$0")" && pwd)"
cd "$TOOLS/.." || exit 1

# ── 焦点归还（2026-11-09 实测补上）──────────────────────────────────────
# 上面那些命令行参数救不了焦点：Godot 创建窗口时会**抢一次系统前台**，
# 而运行时 API 撤不回来（`window_set_flag(NO_FOCUS)` 设得太晚，
# `override.cfg` 在 --path 模式下 Godot 根本不读，`--feature` 参数不存在）。
#
# 所以：启动前记下用户的前台窗口 → Godot 起来 0.7s 后把焦点还回去。
# 实现见 _focus.ps1。没有 PowerShell 时退回原样（至少窗口在屏幕外）。
PS="powershell.exe"
run_godot() {
  "$GODOT" --path . --position -4000,-4000 --resolution 1280x720 --windowed \
    --audio-driver Dummy --script "$SCRIPT" -- --no-capture "$@"
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

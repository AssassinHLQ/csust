#!/usr/bin/env bash
# 一轮验证：先冒烟（改坏没有），再量换窗口卡顿基线。
set -u
cd "$(dirname "$0")/.." || exit 1
mkdir -p _log
echo "########## 冒烟 ##########"
bash _tools/boot_check.sh 600 2>&1 | grep -E 'SCRIPT ERROR|Parse Error|ERROR|error|Cannot|Invalid' | head -30
echo "########## 换窗口卡顿基线 ##########"
bash _tools/run_shot.sh res://scripts/_probe_switch_hitch.gd 2>&1 | grep -v '^\[' | head -5
grep -E '^\[hitch\]' _log/switch_hitch.txt 2>/dev/null | tr -d '\r'

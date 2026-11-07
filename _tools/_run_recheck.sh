#!/usr/bin/env bash
# 复测：同一个模型连跑两次，看帧时间是不是稳定（排除测量噪声/着色器缓存差异）。
set -u
cd "$(dirname "$0")/.." || exit 1
for i in 1 2; do
  echo "--- 第 $i 次 ---"
  bash _tools/run_shot.sh res://scripts/_probe_model_cost.gd -- \
    --model=res://models/_wip_esports_hotel/esports_hotel_final.glb \
    --label="Basis 复测 $i" 2>&1 | grep -E '显存|帧时间|draw call'
done

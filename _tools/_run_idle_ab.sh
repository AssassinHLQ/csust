#!/usr/bin/env bash
# 量「静止帧复用」到底值多少：同一档 base，跳过开 / 关各跑一遍。
# 相机在探针里是静止的，所以「关」= 老行为（每帧全量重算），「开」= 复用上一帧。
set -u
cd "$(dirname "$0")/.." || exit 1
mkdir -p _log
{
  echo "########## 静止帧复用：开（默认） ##########"
  bash _tools/run_shot.sh res://scripts/_probe_frame_cost.gd -- --res=1600x900 --scale=0.5 2>&1 | grep -E '^\[cost\] (场景|泼溅|base|no_shadow|lean)'
  echo "########## 静止帧复用：关 ##########"
  bash _tools/run_shot.sh res://scripts/_probe_frame_cost.gd -- --res=1600x900 --scale=0.5 --gdgs-idle-skip=off 2>&1 | grep -E '^\[cost\] (场景|泼溅|base|no_shadow|lean)'
} > _log/idle_skip_ab.txt 2>&1
cat _log/idle_skip_ab.txt

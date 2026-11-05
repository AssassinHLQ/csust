#!/usr/bin/env bash
# 跑「帧成本 A/B」两轮：带泼溅 + 关泼溅（后者用来算泼溅自己占多少）。
# 两轮串行跑，避免两个 Godot 抢 GPU 把数字搅浑。
set -u
cd "$(dirname "$0")/.." || exit 1
mkdir -p _log
{
  echo "########## A：带泼溅 ##########"
  bash _tools/run_shot.sh res://scripts/_probe_frame_cost.gd -- --res=1600x900 --scale=0.5
  echo "########## B：--splat=off ##########"
  bash _tools/run_shot.sh res://scripts/_probe_frame_cost.gd -- --res=1600x900 --scale=0.5 --splat=off
} > _log/frame_cost_run.txt 2>&1
echo "done rc=$?"

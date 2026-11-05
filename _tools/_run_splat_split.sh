#!/usr/bin/env bash
# 泼溅成本分段：正常 / 跳排序 / 关泼溅，各扫 0.25、0.5、1.0 三个缩放。
# 三者相减即得「排序 / 投影+raster / 非泼溅底子」。
set -u
cd "$(dirname "$0")/.." || exit 1
mkdir -p _log
{
  for extra in "" "--gdgs-skip-sort" "--splat=off"; do
    echo "########## 对照：${extra:-（正常）} ##########"
    bash _tools/run_shot.sh res://scripts/_probe_splat_scaling.gd -- \
      --gdgs-idle-skip=off --scales=0.25,0.5,1.0 $extra 2>&1 \
      | grep -E '^\[split\]'
  done
} > _log/splat_split_run.txt 2>&1
cat _log/splat_split_run.txt

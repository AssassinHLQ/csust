"""从数据里精确解出「SOG 绝对坐标 → GGS bin 世界坐标」的相似变换。

背景（2026-11-11）
------------------
包体优化要把校园细层 1,406 MB 的 `campus_chunks10w/*.bin` 换成 ~85 MB 的
分块 SOG（`splatdata/campus_sog/fine/*.sogdata`），运行时现场解码。

但两者坐标系不同：

  * `.bin` 是 **世界坐标** —— `_export_campus_ggs_bin.gd` 用
    `Campus.splat_node.global_transform` 把点烘到世界（position 走 M，
    covariance 走 R·C·Rᵀ·s²）。
  * SOG 块是 **模型局部/绝对坐标** —— `SogRuntime.load_sog` 解出来的原始值。

所以运行时必须把 SOG 解出的点乘上同一个 M。M 由 `world_scale=75` +
`Campus` 节点自身约 1.2° 的旋转 + auto_place 偏移组成，手算容易错
（1.2° 在 500 m 尺度上就是 10 m）。本脚本改成**从数据反解**：

  1. 用 Pillow 解 `school_playable.sogdata` 的 means_l/means_u → 绝对坐标
  2. 复刻 `splat_scene.gd::content_bounds` + `_crop_resource` 的裁剪规则，
     得到与 `campus_ggs.bin` **逐点同序**的保留索引
  3. 按索引配对，最小二乘解 A / t（world = A·p + t）
  4. 校验 A 是「旋转 × 均匀缩放」，并输出残差

产物：`splatdata/campus_sog/frame.json`

    {
      "basis":  [9 floats],   # Transform3D 的 basis（列优先，同 .tscn 写法）
      "origin": [3 floats],
      "scale":  float,
      "quat":   [x, y, z, w],
      "src_points": int, "kept": int,
      "residual_rms": float, "residual_max": float
    }

用法：
    python tools/fit_campus_frame.py
"""

import io
import json
import os
import sys
import zipfile

import numpy as np
from PIL import Image

# Windows 控制台默认 GBK，直接 print 中文/符号会炸
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOG = os.path.join(ROOT, "splatdata", "school_playable.sogdata")
BIN = os.path.join(ROOT, "campus_ggs.bin")
OUT = os.path.join(ROOT, "splatdata", "campus_sog", "frame.json")

# 与 splat_scene.gd 的默认值一致
CROP_MARGIN = 0.5
SAMPLES = 20000
BYTES_PER_SPLAT = 240


def unlog(v):
    return np.sign(v) * (np.exp(np.abs(v)) - 1.0)


def sog_positions():
    """解出全部点的**绝对**坐标（未减 center）。"""
    z = zipfile.ZipFile(SOG)
    meta = json.loads(z.read("meta.json"))
    n = int(meta["count"])
    mins = np.array(meta["means"]["mins"], dtype=np.float64)
    maxs = np.array(meta["means"]["maxs"], dtype=np.float64)

    def atlas(name):
        img = Image.open(io.BytesIO(z.read(name)))
        return np.asarray(img.convert("RGB"), dtype=np.uint8).reshape(-1, 3)[:n]

    lo = atlas(meta["means"]["files"][0]).astype(np.uint32)
    hi = atlas(meta["means"]["files"][1]).astype(np.uint32)
    q = (hi << 8) | lo
    lin = mins + (maxs - mins) * (q.astype(np.float64) / 65535.0)
    return unlog(lin)


def kept_indices(pos):
    """复刻 content_bounds(20000 采样 + 0.1‰/99.9‰) + _crop_resource(外扩 0.5)。"""
    n = len(pos)
    step = max(1, n // max(1, SAMPLES))
    sample = pos[0:n:step]
    lo_idx = int(len(sample) * 0.001)
    hi_idx = min(int(len(sample) * 0.999), len(sample) - 1)
    cmin = sample.min(axis=0)
    cmax = sample.max(axis=0)
    for axis in range(3):
        col = np.sort(sample[:, axis])
        cmin[axis] = col[lo_idx]
        cmax[axis] = col[hi_idx]
    box_lo = cmin - CROP_MARGIN
    box_hi = cmax + CROP_MARGIN
    inside = np.all((pos >= box_lo) & (pos <= box_hi), axis=1)
    return np.nonzero(inside)[0], cmin, cmax


def bin_positions(count):
    mm = np.memmap(BIN, dtype=np.float32, mode="r",
                   shape=(os.path.getsize(BIN) // BYTES_PER_SPLAT, 60))
    assert len(mm) == count, "bin 点数与裁剪结果不一致：%d vs %d" % (len(mm), count)
    return np.asarray(mm[:, 0:3], dtype=np.float64)


def main():
    for p in (SOG, BIN):
        if not os.path.exists(p):
            print("缺文件：%s" % p)
            return 1

    print("[fit] 解 SOG 坐标 …")
    pos = sog_positions()
    print("[fit] 源点数 %d" % len(pos))

    keep, cmin, cmax = kept_indices(pos)
    print("[fit] content_bounds min %s max %s" % (np.round(cmin, 4), np.round(cmax, 4)))
    print("[fit] 裁剪后保留 %d（丢 %d）" % (len(keep), len(pos) - len(keep)))

    print("[fit] 读 %s …" % os.path.basename(BIN))
    world = bin_positions(len(keep))

    src = pos[keep]
    # world = A·src + t 的最小二乘解
    src_c = src.mean(axis=0)
    world_c = world.mean(axis=0)
    s0 = src - src_c
    w0 = world - world_c
    A = np.linalg.lstsq(s0, w0, rcond=None)[0].T          # (3,3)
    t = world_c - A @ src_c

    resid = world - (src @ A.T + t)
    rms = float(np.sqrt((resid ** 2).sum(axis=1).mean()))
    rmax = float(np.abs(resid).max())
    # A 应等于 s·R：列范数相等、两两正交
    col = np.linalg.norm(A, axis=0)
    scale = float(col.mean())
    R = A / scale
    ortho_err = float(np.abs(R.T @ R - np.eye(3)).max())
    det = float(np.linalg.det(R))

    # ⚠️ 轴序踩坑点：Godot 的 `Basis(x_axis, y_axis, z_axis)` 收的是**三根轴**
    #    （= 数学矩阵 A 的**列**），`Basis * v = x_axis*v.x + y_axis*v.y + z_axis*v.z`。
    #    这里直接输出 A 的三列，运行时 `Basis(...)` 一构即可，不需要再做转置。
    #    （自检：这三列的旋转部分应当逐位等于 next_level.tscn 里 Campus 节点的
    #      transform —— 本喵核对过，吻合到 5 位小数。）
    axes = [[float(v) for v in A[:, c]] for c in range(3)]
    origin = [float(v) for v in t]

    print()
    print("[fit] scale      = %.6f   (world_scale 名义值 75)" % scale)
    print("[fit] 列范数      = %s" % np.round(col, 6))
    print("[fit] 正交误差    = %.3e   det=%.6f" % (ortho_err, det))
    print("[fit] 残差 RMS    = %.6f m   最大 %.6f m" % (rms, rmax))
    print("[fit] origin     = %s" % np.round(t, 4))
    print("[fit] 轴（列，未归一化，已含 scale）：")
    for c in range(3):
        print("       %s" % np.round(A[:, c], 6))
    print()

    ok = ortho_err < 1e-5 and abs(det - 1.0) < 1e-5 and rms < 0.01
    if not ok:
        print("[fit] ★ 不像「旋转×均匀缩放」，或者残差过大 —— 方案前提不成立，别用")
        return 1
    print("[fit] OK：变换是干净的相似变换，残差在毫米级以下")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({
            "_comment": "由 tools/fit_campus_frame.py 解出：SOG 绝对坐标 → GGS 世界坐标。"
                        "运行时 Basis(axes[0],axes[1],axes[2]) 与 origin 组成 A；"
                        "位置 p_w = A*p + origin，协方差 C_w = A*C*Aᵀ（axes 已含 scale，"
                        "所以不要再额外乘 scale²）。",
            "axes": axes,
            "origin": origin,
            "scale": scale,
            "src_points": int(len(pos)),
            "kept": int(len(keep)),
            "content_min": [float(v) for v in cmin],
            "content_max": [float(v) for v in cmax],
            "box_min": [float(v) for v in (cmin - CROP_MARGIN)],
            "box_max": [float(v) for v in (cmax + CROP_MARGIN)],
            "residual_rms": rms,
            "residual_max": rmax,
        }, f, ensure_ascii=False, indent=1)
    print("[fit] 写出 %s" % OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())

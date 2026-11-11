"""生成校园 SOG 分块的运行时清单 `splatdata/campus_sog/chunks.json`。

对应关系
--------
旧：`splatdata/campus_chunks10w/chunks.json` + 100 个 `.bin`（1,406 MB 世界坐标 raw）
新：`splatdata/campus_sog/chunks.json`        +  97 个 `.sogdata`（85 MB 局部坐标）

运行时要做的只有两件事：
  ① `SogRuntime.load_sog(chunk, {"center": Vector3.ZERO, "centroids": <共享调色板>})`
     —— 传 center=ZERO 是关键，否则每块会各自减掉自己的均值、散到原点
  ② 对解出来的点套 `frame` 里的 A：`p_w = A*p + origin`，`C_w = A*C*Aᵀ`
     （A 是从数据反解出来的，不是手算的；见 tools/fit_campus_frame.py）

清单字段
--------
  grid.nx/nz      网格块数（`_split_sog.gd --nx --nz` 打进去的）
  grid.box_min/max  建网格用的 0.1‰~99.9‰ 分位盒（**绝对 SOG 坐标**，未外扩 margin）
  frame.axes/origin  A 的三根轴（列）与平移，见 fit_campus_frame.py
  chunks[].center   该格子的**世界坐标**中心（= A*格子中心 + origin），
                    `campus_ggs.gd::_pick_window` 拿它跟玩家比距离
  chunks[].points   该块点数（decoded 后的 240 B/点记录数）
  coarse            粗层那一份（1×1、stride=4 抽稀）

用法：
    python tools/make_campus_sog_manifest.py
"""

import json
import os
import sys
import zipfile

import numpy as np

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOG_DIR = os.path.join(ROOT, "splatdata", "campus_sog")
FINE_DIR = os.path.join(SOG_DIR, "fine")
COARSE_DIR = os.path.join(SOG_DIR, "coarse")
FRAME = os.path.join(SOG_DIR, "frame.json")
OUT = os.path.join(SOG_DIR, "chunks.json")

EXPECT_FINE_TOTAL = 6144827      # = school_playable 裁剪后（见 fit_campus_frame.py）
EXPECT_COARSE_TOTAL = 1536207    # = 每 4 点留 1（与原 campus_ggs_q4.bin 同序）


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


def sog_count(path):
    with zipfile.ZipFile(path) as z:
        return int(json.loads(z.read("meta.json"))["count"])


def main():
    for p in (FRAME, FINE_DIR, COARSE_DIR):
        if not os.path.exists(p):
            print("缺 %s" % p)
            return 1

    frame = json.load(open(FRAME, encoding="utf-8"))
    A = np.array(frame["axes"], dtype=np.float64).T        # axes 是列 → 转成矩阵
    t = np.array(frame["origin"], dtype=np.float64)

    # 网格盒 = 建网格时用的分位盒（= content_bounds，未外扩 margin）
    box_min = np.array(frame["content_min"], dtype=np.float64)
    box_max = np.array(frame["content_max"], dtype=np.float64)
    box_size = box_max - box_min

    fine = sorted(f for f in os.listdir(FINE_DIR) if f.endswith(".sogdata"))
    if not fine:
        print("fine 目录里没有 .sogdata")
        return 1
    # 从文件名推 nx/nz
    nx = 1 + max(int(f.split("_")[1]) for f in fine)
    nz = 1 + max(int(f.split("_")[2].split(".")[0]) for f in fine)
    print("[man] fine %d 块，网格 %d × %d" % (len(fine), nx, nz))

    chunks = []
    total = 0
    for name in fine:
        _, sx, sz = name.split("_")
        i, j = int(sx), int(sz.split(".")[0])
        p = os.path.join(FINE_DIR, name)
        n = sog_count(p)
        total += n
        if n <= 0:
            continue
        # 与 _split_sog.gd 的分桶同式：格子中心 (i+0.5)/nx
        cell = np.array([
            box_min[0] + (i + 0.5) / nx * box_size[0],
            (box_min[1] + box_max[1]) * 0.5,
            box_min[2] + (j + 0.5) / nz * box_size[2],
        ])
        center = A @ cell + t
        chunks.append({
            "name": "Chunk_%d_%d" % (i, j),
            "i": i, "j": j,
            "center": [round(float(v), 4) for v in center],
            "points": n,
            "sog": rel(p),
        })
    chunks.sort(key=lambda c: (c["j"], c["i"]))

    coarse_files = [f for f in os.listdir(COARSE_DIR) if f.endswith(".sogdata")]
    if len(coarse_files) != 1:
        print("coarse 目录里应当恰好 1 个 .sogdata，实际 %d" % len(coarse_files))
        return 1
    coarse_path = os.path.join(COARSE_DIR, coarse_files[0])
    coarse_n = sog_count(coarse_path)

    print("[man] fine 点数合计 %d（期望 %d）" % (total, EXPECT_FINE_TOTAL))
    print("[man] coarse 点数   %d（期望 %d）" % (coarse_n, EXPECT_COARSE_TOTAL))
    if total != EXPECT_FINE_TOTAL or coarse_n != EXPECT_COARSE_TOTAL:
        print("[man] ★ 点数对不上，说明切分参数或裁剪规则变了 —— 先查清楚再往下走")
        return 1

    sizes = sum(os.path.getsize(os.path.join(FINE_DIR, f)) for f in fine)
    sizes += os.path.getsize(coarse_path) + os.path.getsize(os.path.join(SOG_DIR, "shn_centroids.webp"))
    print("[man] 合计体积 %.1f MB" % (sizes / 1048576.0))

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({
            "_comment": "由 tools/make_campus_sog_manifest.py 生成。SOG 分块 + "
                        "fit_campus_frame.py 解出的相似变换。",
            "grid": {
                "nx": nx, "nz": nz,
                "box_min": [float(v) for v in box_min],
                "box_max": [float(v) for v in box_max],
            },
            "frame": {
                "axes": frame["axes"],
                "origin": frame["origin"],
                "scale": frame["scale"],
                "residual_rms": frame["residual_rms"],
            },
            "centroids": rel(os.path.join(SOG_DIR, "shn_centroids.webp")),
            "chunks": chunks,
            "coarse": {"points": coarse_n, "sog": rel(coarse_path)},
        }, f, ensure_ascii=False, indent=1)
    print("[man] 写出 %s（%d 块）" % (OUT, len(chunks)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

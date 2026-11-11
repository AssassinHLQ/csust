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
    # 默认：细层 14×14 + 粗层
    python tools/make_campus_sog_manifest.py
    # A/B 对照用：全量 1×1（stride=1）单独出一份清单，不带粗层
    python tools/make_campus_sog_manifest.py --fine=full --out=chunks_full.json --no-coarse
"""

import argparse
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
FRAME = os.path.join(SOG_DIR, "frame.json")


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


def sog_count(path):
    with zipfile.ZipFile(path) as z:
        return int(json.loads(z.read("meta.json"))["count"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fine", default="fine", help="细层子目录名（相对 splatdata/campus_sog）")
    ap.add_argument("--coarse", default="coarse", help="粗层子目录名")
    ap.add_argument("--out", default="chunks.json", help="输出清单文件名")
    ap.add_argument("--no-coarse", action="store_true", help="不写粗层条目")
    args = ap.parse_args()

    fine_dir = os.path.join(SOG_DIR, args.fine)
    coarse_dir = os.path.join(SOG_DIR, args.coarse)
    out_path = os.path.join(SOG_DIR, args.out)
    need = [FRAME, fine_dir] + ([] if args.no_coarse else [coarse_dir])
    for p in need:
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

    fine = sorted(f for f in os.listdir(fine_dir) if f.endswith(".sogdata"))
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
        p = os.path.join(fine_dir, name)
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

    # ⚠️ 期望值**从 frame.json 的 `kept` 取**，不要写死常数：
    #    切分参数（nx/nz）一变，有些格子会变空、旧文件不被覆盖，
    #    写死的常数会把「残留把总点数顶多」这种情况放过去。
    expect_fine = int(frame["kept"])
    print("[man] fine 点数合计 %d（frame.json 的 kept = %d）" % (total, expect_fine))
    if total != expect_fine:
        print("[man] ★ 点数对不上 —— 切分参数或裁剪规则变了，先查清楚再往下走")
        return 1

    coarse_entry = None
    sizes = sum(os.path.getsize(os.path.join(fine_dir, f)) for f in fine)
    if not args.no_coarse:
        coarse_files = [f for f in os.listdir(coarse_dir) if f.endswith(".sogdata")]
        if len(coarse_files) != 1:
            print("coarse 目录里应当恰好 1 个 .sogdata，实际 %d" % len(coarse_files))
            return 1
        coarse_path = os.path.join(coarse_dir, coarse_files[0])
        coarse_n = sog_count(coarse_path)
        expect_coarse = expect_fine // 4
        print("[man] coarse 点数   %d（每 4 点留 1 ⇒ 期望约 %d）" % (coarse_n, expect_coarse))
        if abs(coarse_n - expect_coarse) > 2:
            print("[man] ★ 粗层点数对不上，先查清楚再往下走")
            return 1
        coarse_entry = {"points": coarse_n, "sog": rel(coarse_path)}
        sizes += os.path.getsize(coarse_path)
    sizes += os.path.getsize(os.path.join(SOG_DIR, "shn_centroids.webp"))
    print("[man] 合计体积 %.1f MB" % (sizes / 1048576.0))

    doc = {
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
    }
    if coarse_entry is not None:
        doc["coarse"] = coarse_entry
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
    tail = "，含粗层" if coarse_entry is not None else "，无粗层"
    print("[man] 写出 " + str(out_path) + "（" + str(len(chunks)) + " 块" + tail + "）")
    return 0


if __name__ == "__main__":
    sys.exit(main())

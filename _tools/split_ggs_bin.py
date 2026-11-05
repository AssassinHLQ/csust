"""把 `campus_ggs.bin` 按世界坐标切成 10×10 分块（记录**逐字节原样搬运**）。

为什么需要这个脚本（2026-11-05）：
  第②步 `acf6347` 的 97 块是从 SOG 那边导的，坐标系和 `campus_ggs.bin` **不是同一套**：
    · campus_ggs.bin：x 跨度 708、z 跨度 548，z 中心 ≈ −320（和地面网格 CampusFloor
      z=−316.7、576×484 m 对得上）→ 这才是世界坐标；
    · 那 97 块：x 跨度 236、z 跨度 180，z 中心 ≈ −140 → 正好是全量的 **1/3**。
  两者点数、字节数完全相同（6,144,827 点 / 1,474,758,480 B），是同一批数据的两个尺度。
  后果：细层渲染出来是个「1/3 大小的迷你校园」，浮在真正的校园旁边 ——
  这才是 3×3 窗口看起来像「浮空地皮」的真正原因，跟窗口大小无关。

本脚本从 campus_ggs.bin 直接切，所以细层和粗层必然同一套坐标。

网格：拿点数分布的 0.5%~99.5% 分位当范围（避开远飞点把网格撑歪），
     范围外（极少量远飞点）夹到最近的边缘格，保证**一点不丢**。

用法：
    python _tools/split_ggs_bin.py campus_ggs.bin splatdata/campus_chunks10 10 10
输出：
    <outdir>/Chunk_<i>_<j>.bin      97~100 块
    <outdir>/chunks.json            {root, chunks:[{name, center, bin, bytes}]}
                                    center = 该块点的均值（世界坐标，与旧格式一致）
"""

import json
import os
import sys

import numpy as np

REC = 240
FLOATS = 60
BLOCK_RECS = 400_000


def main() -> int:
    if len(sys.argv) != 5:
        print(__doc__)
        return 2
    src, outdir = sys.argv[1], sys.argv[2]
    nx, nz = int(sys.argv[3]), int(sys.argv[4])
    os.makedirs(outdir, exist_ok=True)

    # ---- 第一趟：定网格范围（用分位数，避开远飞点）----
    xs, zs = [], []
    n_total = 0
    with open(src, "rb") as fi:
        while True:
            block = fi.read(REC * BLOCK_RECS)
            if not block:
                break
            n = len(block) // REC
            a = np.frombuffer(block, dtype=np.float32, count=n * FLOATS).reshape(n, FLOATS)
            xs.append(a[:, 0])
            zs.append(a[:, 2])
            n_total += n
    x = np.concatenate(xs)
    z = np.concatenate(zs)
    x0, x1 = np.percentile(x, [0.5, 99.5])
    z0, z1 = np.percentile(z, [0.5, 99.5])
    print("世界范围（0.5%%~99.5%%）x[%.1f, %.1f] z[%.1f, %.1f]" % (x0, x1, z0, z1))
    print("原始极值            x[%.1f, %.1f] z[%.1f, %.1f]" % (x.min(), x.max(), z.min(), z.max()))
    sx = (x1 - x0) / nx
    sz = (z1 - z0) / nz
    print("网格 %d×%d，每格 %.1f × %.1f m" % (nx, nz, sx, sz))
    del x, z, xs, zs

    # ---- 第二趟：流式分配 + 累计中心 ----
    handles = {}
    acc = {}
    for i in range(nx):
        for j in range(nz):
            nm = "Chunk_%d_%d" % (i, j)
            handles[nm] = open(os.path.join(outdir, nm + ".bin"), "wb")
            acc[nm] = [np.zeros(3), 0]          # sum(pos), count
    written = 0
    with open(src, "rb") as fi:
        while True:
            block = fi.read(REC * BLOCK_RECS)
            if not block:
                break
            n = len(block) // REC
            a = np.frombuffer(block, dtype=np.float32, count=n * FLOATS).reshape(n, FLOATS)
            pos = a[:, 0:3]
            i = np.clip(np.floor((pos[:, 0] - x0) / sx).astype(np.int64), 0, nx - 1)
            j = np.clip(np.floor((pos[:, 2] - z0) / sz).astype(np.int64), 0, nz - 1)
            cell = i * nz + j
            view = memoryview(block)
            order = np.argsort(cell, kind="stable")
            cs = cell[order]
            # 每个格子在本块里的连续区间
            uniq, starts = np.unique(cs, return_index=True)
            bounds = list(starts) + [len(cs)]
            for k, c in enumerate(uniq):
                idx = order[bounds[k]:bounds[k + 1]]
                ii, jj = int(c) // nz, int(c) % nz
                nm = "Chunk_%d_%d" % (ii, jj)
                h = handles[nm]
                for t in idx:
                    h.write(view[int(t) * REC:(int(t) + 1) * REC])
                acc[nm][0] += pos[idx].sum(axis=0)
                acc[nm][1] += len(idx)
                written += len(idx)
    for h in handles.values():
        h.close()
    print("写出 %d 点（应等于源 %d）" % (written, n_total))
    if written != n_total:
        print("!! 点数对不上")
        return 1

    # ---- 清单 ----
    # ⚠️ `center` 写**网格几何中心**，不是点的均值：某些格子夹着扫描的远飞点，
    #    均值会被拉出去几十上百米，`_pick_window()` 按中心找最近格就会选歪。
    #    点的均值另存 `mean`，只做诊断用。
    chunks = []
    empty = 0
    for i in range(nx):
        for j in range(nz):
            nm = "Chunk_%d_%d" % (i, j)
            cnt = int(acc[nm][1])
            p = os.path.join(outdir, nm + ".bin")
            if cnt == 0:
                empty += 1
            geo = [round(x0 + (i + 0.5) * sx, 3), 0.0, round(z0 + (j + 0.5) * sz, 3)]
            mean = (acc[nm][0] / max(cnt, 1)).round(1).tolist()
            chunks.append({
                "name": nm,
                "center": geo,
                "mean": mean,
                "points": cnt,
                "bin": os.path.relpath(p, ".").replace("\\", "/"),
                "bytes": os.path.getsize(p),
            })
    root_center = [0.0, 0.0, 0.0]
    manifest = {"root": root_center, "chunks": chunks}
    with open(os.path.join(outdir, "chunks.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print("清单 → %s（%d 块，其中空块 %d）" % (
        os.path.join(outdir, "chunks.json"), len(chunks), empty))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

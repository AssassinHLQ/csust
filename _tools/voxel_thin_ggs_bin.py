"""GGS bin 的**体素抽稀**：把空间切成小立方格，每格只留 1 个高斯点（留不透明度最高的那个）。

比 `decimate_ggs_bin.py` 的「每 N 点留 1」好在哪：
  · 均匀抽稀是**无差别**丢点：树冠里丢掉的点和墙面里丢掉的点一样多，
    于是墙面变稀、大的 splat 顶上来 → 糊；
  · 体素抽稀是**按空间密度**丢点：点越挤的地方丢得越多，稀的地方（墙面/边缘）保住，
    所以同一个点数下结构更清楚。

格式（见 `addons/ggs_campus/shaders/gsplat_projection.glsl` 的 Splat 结构 +
`ply_file.gd::load_gaussian_splats` 的打包顺序）：
  每点 60 个 float32 = 240 字节
  [0..2] 世界坐标 x,y,z    [3] time    [4..9] 协方差    [10] 不透明度    [11] pad
  [12..14] 颜色            [15..59] SH 系数

用法：
    python _tools/voxel_thin_ggs_bin.py <in.bin> <out.bin> <voxel_m>
    python _tools/voxel_thin_ggs_bin.py campus_ggs.bin campus_ggs_vox.bin 0.30

实现是两趟：第一趟流式扫一遍、按体素记下「最不透明的那个 index」；
第二趟再扫一遍、把这些 index 的记录原样写出去（记录不解码，字节级原样搬运，
所以不会动颜色/协方差的任何一位）。
"""

import sys

import numpy as np

REC = 240
FLOATS = 60
BLOCK_RECS = 400_000          # 每块 96 MB 左右的 float32


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    src, dst, voxel = sys.argv[1], sys.argv[2], float(sys.argv[3])
    if voxel <= 0:
        print("voxel 必须 > 0")
        return 2

    # ---- 第一趟：每个体素挑不透明度最高的那个 ----
    best = {}                  # key(int) -> (opacity, abs_index)
    abs_base = 0
    pos_min = np.array([np.inf] * 3)
    pos_max = np.array([-np.inf] * 3)
    with open(src, "rb") as fi:
        while True:
            block = fi.read(REC * BLOCK_RECS)
            if not block:
                break
            n = len(block) // REC
            a = np.frombuffer(block, dtype=np.float32, count=n * FLOATS).reshape(n, FLOATS)
            pos = a[:, 0:3]
            opa = a[:, 10]
            pos_min = np.minimum(pos_min, pos.min(axis=0))
            pos_max = np.maximum(pos_max, pos.max(axis=0))
            ijk = np.floor(pos / voxel).astype(np.int64)
            # 拼成一个 int64 key（每轴 21 位够用：±100 万格）
            key = ((ijk[:, 0] + (1 << 20)) << 42) \
                | ((ijk[:, 1] + (1 << 20)) << 21) \
                | (ijk[:, 2] + (1 << 20))
            # 块内先按 (key, opacity) 排序，再取每个 key 的最后一个（= 最大不透明度）
            order = np.lexsort((opa, key))
            ks = key[order]
            first = np.ones(len(ks), dtype=bool)
            first[1:] = ks[1:] != ks[:-1]
            last = np.ones(len(ks), dtype=bool)
            last[:-1] = ks[1:] != ks[:-1]
            pick = order[last]           # 每个 key 里不透明度最大的那个（块内）
            for local_i in pick:
                k = int(key[local_i])
                o = float(opa[local_i])
                gi = abs_base + int(local_i)
                cur = best.get(k)
                if cur is None or o > cur[0]:
                    best[k] = (o, gi)
            abs_base += n

    keep = sorted(v[1] for v in best.values())
    print("包围盒 x[%.1f, %.1f] y[%.1f, %.1f] z[%.1f, %.1f]  体素 %.2f m"
          % (pos_min[0], pos_max[0], pos_min[1], pos_max[1], pos_min[2], pos_max[2], voxel))
    print("源 %d 点 → 留 %d 点（体素 %d 个，压到 %.1f%%）"
          % (abs_base, len(keep), len(best), 100.0 * len(keep) / max(abs_base, 1)))

    # ---- 第二趟：把选中的记录原样写出去 ----
    keep_arr = np.asarray(keep, dtype=np.int64)
    keep_set = set(keep)
    written = 0
    abs_i = 0
    with open(src, "rb") as fi, open(dst, "wb") as fo:
        while True:
            block = fi.read(REC * BLOCK_RECS)
            if not block:
                break
            n = len(block) // REC
            lo, hi = abs_i, abs_i + n - 1
            sel = keep_arr[(keep_arr >= lo) & (keep_arr <= hi)]
            if sel.size:
                view = memoryview(block)
                for gi in sel:
                    local = int(gi - abs_i)
                    fo.write(view[local * REC:(local + 1) * REC])
                    written += 1
            abs_i += n
    print("写出 %d 点 / %.1f MB → %s"
          % (written, written * REC / 1048576.0, dst))
    assert written == len(keep), "写出点数与计划不符"
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

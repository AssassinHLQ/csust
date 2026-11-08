"""Sanity-check the *record layout* of a Gaussian-splat bin.

Reading a fixed-width float file at the wrong stride yields garbage: positions spread
over a huge range, opacities outside [0,1], covariances that are not positive definite.
This prints the fields the shader actually consumes, so a mis-aligned record is obvious.

Layout the exporter writes (`_export_campus_ggs_bin.gd`, 60 floats / 240 bytes):
    0..2   position xyz        3  pad
    4..9   covariance  xx, yx, zx, yy, zy, zz
    10     opacity             11 pad
    12..59 SH (48 floats)

ASCII only: the console here is cp936 and mangles CJK.
"""

import sys
import numpy as np

STRIDE = 240


def check(path: str, sample: int = 4000) -> None:
    data = np.memmap(path, dtype=np.uint8, mode="r")
    n = len(data) // STRIDE
    print(f"FILE {path}")
    print(f"  bytes={len(data):,}  records@240={n:,}  remainder={len(data) % STRIDE}")
    if n < 10:
        print("  too small\n")
        return
    step = max(1, n // sample)
    idx = np.arange(0, n, step, dtype=np.int64)
    starts = np.repeat(idx * STRIDE, STRIDE) + np.tile(np.arange(STRIDE), idx.size)
    if starts.max() + 1 > len(data):
        starts = starts[starts + 1 <= len(data)]
    rec = np.asarray(data[starts]).reshape(-1, STRIDE).view("<f4")
    print(f"  sampled={rec.shape[0]:,}")

    pos = rec[:, 0:3].astype(np.float64)
    cov = rec[:, 4:10].astype(np.float64)
    opa = rec[:, 10].astype(np.float64)
    sh = rec[:, 12:24].astype(np.float64)   # first 12 SH floats

    def line(name, v):
        finite = np.isfinite(v)
        vf = v[finite]
        if vf.size == 0:
            print(f"  {name}: all non-finite")
            return
        print(f"  {name}: min={vf.min():9.3f} max={vf.max():9.3f} "
              f"mean={vf.mean():9.3f} nonfinite={int((~finite).sum())}")

    for a, ax in enumerate("XYZ"):
        line(f"pos.{ax}", pos[:, a])
    line("opacity", opa)
    in01 = float(np.mean((opa >= 0.0) & (opa <= 1.0)))
    print(f"  opacity in [0,1]: {in01 * 100:6.2f}%   <== should be ~100% for a valid layout")
    line("cov.xx", cov[:, 0])
    line("cov.yy", cov[:, 3])
    line("cov.zz", cov[:, 5])
    pos_def = float(np.mean((cov[:, 0] > 0) & (cov[:, 3] > 0) & (cov[:, 5] > 0)))
    print(f"  cov diag > 0:     {pos_def * 100:6.2f}%   <== should be ~100%")
    line("SH[0]", sh[:, 0])
    line("SH[1]", sh[:, 1])

    # 第 3 个 float 是 shader 结构体里的 `float time`。
    #
    # 这个字段决定了 shader 的**入场动画**：
    #     float splat_time = 时间uniform - splat.time;
    #     float time_factor = ease_out_cubic(clamp(splat_time, 0, 1));
    # 导出器给每个 splat 写的值如果是 0，而 uniform 是「开游戏至今秒数」，
    # 那么开机后第 1 秒里所有椭球都会被放大到 2 倍、淡入、还带一整屏的位移。
    # 如果写的是别的（尤其负数或很大的数），就会永久停在「动画开始那一帧」。
    tm = rec[:, 3].astype(np.float64)
    finite = np.isfinite(tm)
    tf = tm[finite]
    if tf.size:
        uniq = np.unique(tf)
        print(f"  time(第3个float): min={tf.min():.4f} max={tf.max():.4f} "
              f"mean={tf.mean():.4f} 不同取值={uniq.size}")
        if uniq.size <= 4:
            print(f"                    取值 {uniq.tolist()}")
        print("                    <== 应当全为 0.0（导出器只写位置/协方差/透明度/SH）")
    else:
        print("  time(第3个float): 全非有限值")
    print()


if __name__ == "__main__":
    for p in sys.argv[1:]:
        try:
            check(p)
        except Exception as exc:  # noqa: BLE001
            print(f"FILE {p}\n  ERROR {type(exc).__name__}: {exc}\n")

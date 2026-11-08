"""Try several record strides on a splat bin and report which one looks like a point cloud.

A real campus cloud is bottom heavy (ground + low structures), so its Y median sits
well below the middle of the Y range and its coordinates are modest (tens of metres).
Reading a fixed-width float file at the *wrong* stride instead yields values that are
spread roughly uniformly over a huge range, with the median landing on the midpoint.

ASCII-only output: the Windows console here is cp936 and mangles CJK.
"""

import sys
import numpy as np


def probe(path: str, stride: int) -> None:
    data = np.memmap(path, dtype=np.uint8, mode="r")
    n = len(data) // stride
    if n < 200:
        print(f"  stride={stride:5d}  too few records ({n})")
        return
    step = max(1, n // 4000)
    idx = np.arange(0, n, step, dtype=np.int64)
    starts = np.repeat(idx * stride, 12) + np.tile(np.arange(12), idx.size)
    if starts.max() + 1 > len(data):
        print(f"  stride={stride:5d}  runs past EOF")
        return
    xyz = np.asarray(data[starts]).reshape(-1, 12).view("<f4").reshape(-1, 3).astype(np.float64)
    y = xyz[:, 1]
    finite = np.isfinite(xyz).all(axis=1)
    n_bad = int((~finite).sum())
    yf = y[finite]
    if yf.size == 0:
        print(f"  stride={stride:5d}  all non-finite")
        return
    lo, hi = float(yf.min()), float(yf.max())
    med = float(np.median(yf))
    mid = (lo + hi) * 0.5
    # "code-like" = plausible scale, bottom heavy, mostly finite
    plausible = (hi - lo) < 500.0 and abs(med - mid) > (hi - lo) * 0.05 and n_bad == 0
    flag = "  <== looks like real points" if plausible else ""
    print(f"  stride={stride:5d} recs={n:9,}  Y[{lo:10.2f},{hi:10.2f}] span={hi - lo:9.2f} "
          f"med-mid={med - mid:+8.2f} nonfinite={n_bad}{flag}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(f"FILE {p}")
        for s in (60, 120, 240, 300, 480, 960):
            try:
                probe(p, s)
            except Exception as exc:  # noqa: BLE001
                print(f"  stride={s:5d}  ERROR {type(exc).__name__}: {exc}")
        print()

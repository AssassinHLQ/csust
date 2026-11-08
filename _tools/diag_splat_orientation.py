"""Measure which way up the campus Gaussian-splat bins are.

WHY THIS EXISTS
---------------
The room splat goes through the GDGS addon, which multiplies every splat model by
`Basis.from_euler(Vector3(0, 0, -PI))` (180 deg about Z, i.e. X and Y both negated)
-- see `addons/gdgs/runtime/nodes/gaussian_splat_node.gd::get_model_orientation_correction()`.

The campus splat goes through a *different* addon (GGS, `addons/ggs_campus/`), whose
projection shader does `vec3 splat_pos = splat.position*model_scale;` -- a scalar
scale only, no orientation correction.

`_export_campus_ggs_bin.gd` bakes `M = node.global_transform` into the positions.
So whether the campus bin is already flipped depends on whether the GDGS node had
that correction applied at export time. This script answers that from the data
instead of by eye.

CRITERION
---------
A campus is mostly ground plus low structures, so the point cloud is bottom heavy.
  Y up   => median Y sits well BELOW the middle of the Y range.
  Y down => median Y sits well ABOVE it.

BIN LAYOUT (`_export_campus_ggs_bin.gd`)
----------------------------------------
240 bytes / 60 floats per Gaussian:
    [0..2] position xyz   [3] pad
    [4..9] covariance (xx, yx, zx, yy, zy, zz)   [10] opacity   [11] pad
    [12..59] SH

ASCII-only on purpose: the Windows console here is cp936 and mangles CJK labels.
"""

import sys
import numpy as np

STRIDE = 240


def scan(path: str, step: int = 200) -> None:
    data = np.memmap(path, dtype=np.uint8, mode="r")
    n = len(data) // STRIDE
    print(f"FILE {path}")
    print(f"  bytes={len(data):,}  records={n:,}  remainder={len(data) % STRIDE}")

    idx = np.arange(0, n, step, dtype=np.int64)
    off = idx * STRIDE
    # gather the 12-byte position header of each sampled record
    starts = np.repeat(off, 12) + np.tile(np.arange(12), idx.size)
    buf = np.asarray(data[starts]).reshape(-1, 12)
    xyz = buf.view("<f4").reshape(-1, 3).astype(np.float64)

    print(f"  sampled={len(xyz):,} (every {step}th)")
    for a, name in enumerate("XYZ"):
        v = xyz[:, a]
        print(f"    {name}: min={v.min():9.2f} max={v.max():9.2f} "
              f"mean={v.mean():9.2f} span={v.max() - v.min():9.2f}")

    y = xyz[:, 1]
    lo, hi = float(y.min()), float(y.max())
    mid = (lo + hi) * 0.5
    med = float(np.median(y))
    band = (hi - lo) * 0.08
    print(f"  median_Y={med:9.2f}  midpoint={mid:9.2f}  delta={med - mid:+9.2f}")
    if med < mid - band:
        verdict = "Y-UP   (median in the lower half) -> orientation looks CORRECT"
    elif med > mid + band:
        verdict = "Y-DOWN (median in the upper half) -> this file IS FLIPPED"
    else:
        verdict = "AMBIGUOUS (median near midpoint) -> do not conclude from this file"
    print(f"  VERDICT: {verdict}")
    print()


if __name__ == "__main__":
    step = 200
    args = [a for a in sys.argv[1:]]
    if args and args[0].startswith("--step="):
        step = int(args.pop(0).split("=")[1])
    for p in args:
        try:
            scan(p, step)
        except Exception as exc:  # noqa: BLE001 - report and keep going
            print(f"FILE {p}\n  ERROR {type(exc).__name__}: {exc}\n")

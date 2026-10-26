"""在 `g3_desk.png` 上叠候选碰撞盒（3D 线框），一眼看得出贴不贴合。

用 `room_measure.py` 的同一套投影（已用红方块校准，误差 1.6 px）。
改 `CANDIDATES` 里的数字重跑即可迭代，不用重开 Godot。
"""
import math
import sys

import numpy as np
from PIL import Image, ImageDraw

SRC = r"C:\Users\WY157\Desktop\GODOT\_arisu_captures\_fix1026\g3_desk.png"
DST = r"C:\Users\WY157\Desktop\GODOT\_arisu_captures\_fix1026\g5_boxes.png"
CAM = np.array([1.20, 2.80, 6.80])
TARGET = np.array([2.00, 0.20, 2.20])
FOV_DEG = 60.0
UP = np.array([0.0, 1.0, 0.0])

# 候选碰撞盒：(名字, 中心, 尺寸, 颜色)
# 迭代记录（对着 g5_crop.png 修）：
#   A: 中心 (0.25, 0.39, 2.25) 尺寸 (1.62,0.78,1.72)
#      → 右沿咬到桌沿了，但**左沿偏左半米、整体偏北**（框跑到桌子左边空地上）。
#   B: 左沿 +0.45、右沿不动 ⇒ 中心 x 0.25 → 0.475、宽 1.62 → 1.35；
#      整体往南挪 0.35（z 中心 2.25 → 2.60）。
CANDIDATES = [
    ("desk_B", (0.475, 0.39, 2.60), (1.35, 0.78, 1.60), (255, 0, 255)),
]


def basis():
    f = TARGET - CAM
    f = f / np.linalg.norm(f)
    z = -f
    x = np.cross(UP, z)
    x = x / np.linalg.norm(x)
    y = np.cross(z, x)
    return x, y / np.linalg.norm(y), f


XA, YA, FW = basis()


def project(p, w, h):
    d = np.asarray(p, float) - CAM
    depth = float(d @ FW)
    if depth <= 1e-6:
        return None
    tan = math.tan(math.radians(FOV_DEG) * 0.5)
    aspect = w / h
    nx = float(d @ XA) / (depth * tan * aspect)
    ny = float(d @ YA) / (depth * tan)
    return ((nx * 0.5 + 0.5) * w, (0.5 - ny * 0.5) * h)


def corners(centre, size):
    cx, cy, cz = centre
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    out = {}
    for sx, sn in ((-1, "w"), (1, "e")):
        for sy, sy2 in ((-1, "b"), (1, "t")):
            for sz, sz2 in ((-1, "n"), (1, "s")):
                out[f"{sn}{sy2}{sz2}"] = (cx + sx * hx, cy + sy * hy, cz + sz * hz)
    return out


EDGES = [
    # 底面 4 条
    ("wbn", "ebn"), ("ebn", "ebs"), ("ebs", "wbs"), ("wbs", "wbn"),
    # 顶面 4 条
    ("wtn", "etn"), ("etn", "ets"), ("ets", "wts"), ("wts", "wtn"),
    # 竖着 4 条
    ("wbn", "wtn"), ("ebn", "etn"), ("ebs", "ets"), ("wbs", "wts"),
]


def main():
    im = Image.open(SRC).convert("RGB")
    w, h = im.size
    dr = ImageDraw.Draw(im)
    for name, centre, size, col in CANDIDATES:
        cs = corners(centre, size)
        pp = {k: project(v, w, h) for k, v in cs.items()}
        for a, b in EDGES:
            if pp.get(a) and pp.get(b):
                dr.line([pp[a], pp[b]], fill=col, width=4)
        print(f"{name}: 中心 {centre} 尺寸 {size}")
        # 报一下底面的世界范围（真正要输进 .tscn 的数）
        cx, cy, cz = centre
        print(f"   AABB  x {cx - size[0] / 2:+.3f} ~ {cx + size[0] / 2:+.3f}"
              f"  y {cy - size[1] / 2:+.3f} ~ {cy + size[1] / 2:+.3f}"
              f"  z {cz - size[2] / 2:+.3f} ~ {cz + size[2] / 2:+.3f}")
    im.save(DST)
    print(f"\n已写 {DST}")
    crop = im.crop((700, 200, 1500, 850)).resize((1600, 1300), Image.LANCZOS)
    cp = DST.replace("g5_boxes", "g5_crop")
    crop.save(cp)
    print(f"已写 {cp}")


if __name__ == "__main__":
    main()

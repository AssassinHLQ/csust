"""在 `g3_desk.png` 里按颜色找出**木色家具**，聚类成矩形，再反投影成世界坐标。

投影数学已在 `room_measure.py` 里用红方块校准过：
    预测 (1.80, 0.05, 2.60) → 像素 (1250.6, 744.8)
    实测红块中心            → 像素 (1249.0, 757.0)
    反投影回来              = (1.779, 0.050, 2.694)   期望 (1.800, 0.050, 2.600)
误差 1.6 px / 9 cm，够用。

⚠️ 反投影的是**地面（y = 0）**上的点：一块木色像素如果是桌面（y ≈ 0.78），
   它在地面上的对应点会比真实桌脚**偏近相机**。所以这里量的是「桌面对应的地面投影」，
   拿来定碰撞盒时要**往外放一点点**（碰撞盒宁可略小，见 `game.gd` 里那段）。
"""
import json
import math
import os

import numpy as np
from PIL import Image

IMG = r"C:\Users\WY157\Desktop\GODOT\_arisu_captures\_fix1026\g3_desk.png"
OUT_JSON = r"C:\Users\WY157\Desktop\GODOT\_arisu_captures\_fix1026\desk_boxes.json"
CAM = np.array([1.20, 2.80, 6.80])
TARGET = np.array([2.00, 0.20, 2.20])
FOV_DEG = 60.0
UP = np.array([0.0, 1.0, 0.0])
## 桌面高度（米）。见 `_probe_art_desk_splat.gd` 的图：那张木办公桌台面约 0.78 m。
DESK_TOP = 0.78


def basis():
    f = TARGET - CAM
    f = f / np.linalg.norm(f)
    z = -f
    x = np.cross(UP, z)
    x = x / np.linalg.norm(x)
    y = np.cross(z, x)
    return x, y / np.linalg.norm(y), f


XA, YA, FW = basis()


def unproject(sx, sy, w, h, plane_y=0.0):
    tan = math.tan(math.radians(FOV_DEG) * 0.5)
    aspect = w / h
    nx = (sx / w * 2.0 - 1.0)
    ny = (1.0 - sy / h * 2.0)
    ray = XA * (nx * tan * aspect) + YA * (ny * tan) + FW
    if abs(ray[1]) < 1e-9:
        return None
    t = (plane_y - CAM[1]) / ray[1]
    if t <= 0:
        return None
    return CAM + ray * t


def main():
    im = Image.open(IMG).convert("RGB")
    w, h = im.size
    a = np.asarray(im).astype(np.int16)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]

    # 木色：偏暖、饱和度中等偏上、亮度中等（桌面那块橡木）
    wood = (r > 90) & (r < 215) & (g > 55) & (g < 175) & (b < 135) \
        & (r - b > 45) & (r >= g) & (g >= b - 10)
    # 只在「画室中部」找，排掉左边的暖色墙面和右边的纸箱
    mask = np.zeros_like(wood)
    mask[300:1100, 700:1500] = True
    wood = wood & mask
    print(f"木色像素 {int(wood.sum())} 个")

    # 连通块（简单 4 连通 BFS，numpy 里的等价物：scipy 不在，手写）
    from collections import deque
    seen = np.zeros_like(wood, dtype=bool)
    boxes = []
    ys, xs = np.nonzero(wood)
    if len(xs) == 0:
        print("!! 没有木色像素")
        return
    # 只在有木色的包围内做 BFS，避免 2560×1334 全扫
    y0, y1 = ys.min(), ys.max() + 1
    x0, x1 = xs.min(), xs.max() + 1
    sub = wood[y0:y1, x0:x1]
    H, W = sub.shape
    flat = sub.ravel()
    labels = np.full(flat.shape, -1, dtype=np.int32)
    cur = 0
    for start in range(flat.size):
        if not flat[start] or labels[start] >= 0:
            continue
        q = deque([start])
        labels[start] = cur
        cnt = 0
        mnx = mny = 10 ** 9
        mxx = mxy = -1
        while q:
            p = q.popleft()
            py, px = divmod(p, W)
            cnt += 1
            mnx = min(mnx, px); mxx = max(mxx, px)
            mny = min(mny, py); mxy = max(mxy, py)
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny2, nx2 = py + dy, px + dx
                if 0 <= ny2 < H and 0 <= nx2 < W:
                    q2 = ny2 * W + nx2
                    if flat[q2] and labels[q2] < 0:
                        labels[q2] = cur
                        q.append(q2)
        if cnt >= 3000:
            boxes.append({"px": [int(mnx + x0), int(mny + y0),
                                 int(mxx + x0), int(mxy + y0)], "count": cnt})
        cur += 1

    boxes.sort(key=lambda d: -d["count"])
    print(f"大连通块 {len(boxes)} 个\n")

    out = []
    for i, bx in enumerate(boxes[:8]):
        px0, py0, px1, py1 = bx["px"]
        # 四角 + 中心，**两个平面都算**：
        #   y = 0     → 地面（桌脚所在的平面）
        #   y = 0.78  → 桌面高度（那堆木色像素本身所在的平面）
        # ⚠️ 木色像素是**桌面**（y ≈ 0.78），投到 y = 0 会被透视拉长成一条，
        #    跨好几个米 —— 必须投到它自己的高度才对得上真实占位。
        corners = {}
        for plane, tag in ((0.0, "g"), (DESK_TOP, "d")):
            for nm, (sx, sy) in {
                "nw": (px0, py0), "ne": (px1, py0),
                "sw": (px0, py1), "se": (px1, py1),
                "c": ((px0 + px1) / 2, (py1 + py0) / 2),
            }.items():
                p = unproject(sx, sy, w, h, plane)
                if p is not None:
                    corners[f"{nm}_{tag}"] = [round(float(p[0]), 3), plane,
                                              round(float(p[2]), 3)]
        print(f"块 #{i}: 像素 x {px0}~{px1}  y {py0}~{py1}  ({bx['count']} px)")
        print(f"    地面投影（y=0）：", end="")
        for nm in ("nw", "ne", "sw", "se"):
            c = corners.get(f"{nm}_g")
            if c:
                print(f" {nm}({c[0]:+.2f},{c[2]:+.2f})", end="")
        print()
        print(f"    桌面投影（y={DESK_TOP}）：", end="")
        for nm in ("nw", "ne", "sw", "se"):
            c = corners.get(f"{nm}_d")
            if c:
                print(f" {nm}({c[0]:+.2f},{c[2]:+.2f})", end="")
        print()
        d_pts = [corners[k] for k in corners if k.endswith("_d")]
        if d_pts:
            xs2 = [p[0] for p in d_pts]
            zs2 = [p[2] for p in d_pts]
            print(f"    ⇒ 桌面水平范围 x {min(xs2):+.2f} ~ {max(xs2):+.2f}"
                  f"（宽 {max(xs2) - min(xs2):.2f}）、"
                  f"z {min(zs2):+.2f} ~ {max(zs2):+.2f}（深 {max(zs2) - min(zs2):.2f}）")
        out.append({"px": bx["px"], "count": bx["count"], "corners": corners})
        print()

    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"已写 {OUT_JSON}")


if __name__ == "__main__":
    main()

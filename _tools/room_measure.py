"""把 `g3_desk.png` 里那几件家具的像素位置，反投影成世界坐标（y = 0 的地面）。

为什么不用射线：画室 609 是高斯泼溅，泼溅**没有碰撞体**，射线只打得到 5 面墙。

相机参数来自 `scripts/_probe_room_grid3.gd` 第一次出图那一档：
    global_position = (sp.x - 0.60, 2.80, sp.z + 4.20)  = (1.20, 2.80, 6.80)
    look_at         = (sp.x + 0.20, 0.20, sp.z - 0.40) = (2.00, 0.20, 2.20)
    fov = 60（竖直）, 图像 = 2560 × 1334
相机竖直 up = (0,1,0)；Godot 相机看 −Z。
"""
import json
import math
import sys

import numpy as np
from PIL import Image

IMG = r"C:\Users\WY157\Desktop\GODOT\_arisu_captures\_fix1026\g3_desk.png"
CAM = np.array([1.20, 2.80, 6.80])
TARGET = np.array([2.00, 0.20, 2.20])
FOV_DEG = 60.0
UP = np.array([0.0, 1.0, 0.0])


def basis():
    f = TARGET - CAM
    f /= np.linalg.norm(f)
    z = -f
    x = np.cross(UP, z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    y /= np.linalg.norm(y)
    return x, y, f


X_AXIS, Y_AXIS, FWD = basis()


def project(p, w, h):
    """世界点 → 屏幕像素"""
    d = np.asarray(p, float) - CAM
    depth = float(d @ FWD)
    if depth <= 1e-6:
        return None
    tan = math.tan(math.radians(FOV_DEG) * 0.5)
    aspect = w / h
    nx = float(d @ X_AXIS) / (depth * tan * aspect)
    ny = float(d @ Y_AXIS) / (depth * tan)
    return ((nx * 0.5 + 0.5) * w, (0.5 - ny * 0.5) * h)


def unproject(sx, sy, w, h, plane_y=0.0):
    """屏幕像素 + 「落在 y = plane_y 的水平面上」→ 世界点"""
    tan = math.tan(math.radians(FOV_DEG) * 0.5)
    aspect = w / h
    nx = (sx / w * 2.0 - 1.0)
    ny = (1.0 - sy / h * 2.0)
    ray = X_AXIS * (nx * tan * aspect) + Y_AXIS * (ny * tan) + FWD
    if abs(ray[1]) < 1e-9:
        return None
    t = (plane_y - CAM[1]) / ray[1]
    if t <= 0:
        return None
    return CAM + ray * t


def main():
    im = Image.open(IMG).convert("RGB")
    w, h = im.size
    print(f"图像 {w} × {h}")
    print(f"相机 {CAM}  看向 {TARGET}  fov {FOV_DEG}")

    # ── ① 找红方块（老师站位 1.80, 0.05, 2.60）—— 用来自检投影对不对 ──
    a = np.asarray(im).astype(np.int16)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    red = (r > 150) & (g < 90) & (b < 90)
    ys, xs = np.nonzero(red)
    if len(xs) == 0:
        print("!! 没找到红方块")
    else:
        # 只取最大的一团（用中位数附近筛一遍，避免零散噪点）
        mx, my = np.median(xs), np.median(ys)
        keep = (np.abs(xs - mx) < 120) & (np.abs(ys - my) < 120)
        xs, ys = xs[keep], ys[keep]
        cx, cy = xs.mean(), ys.mean()
        print(f"\n红方块：{len(xs)} px，中心像素 ({cx:.1f}, {cy:.1f})，"
              f"范围 x {xs.min()}~{xs.max()}  y {ys.min()}~{ys.max()}")
        pred = project([1.80, 0.05, 2.60], w, h)
        print(f"  投影预测 (1.80, 0.05, 2.60) → 像素 ({pred[0]:.1f}, {pred[1]:.1f})"
              f"   误差 ({cx - pred[0]:+.1f}, {cy - pred[1]:+.1f}) px")
        back = unproject(cx, cy, w, h, plane_y=0.05)
        print(f"  反投影回来 = ({back[0]:.3f}, {back[1]:.3f}, {back[2]:.3f})"
              f"   期望 (1.800, 0.050, 2.600)")

    # ── ② 反投影桌面四角 ──
    #    像素值由人眼从 g3_desk.png 上读（这张图里桌子左前方那个角最清楚）
    pts = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
    if not pts:
        print("\n用法：python room_measure.py '{\"desk_bl\": [x, y], ...}'")
        print("（键名随便起，值 = 该点在图像里的像素坐标；会按 y=0 的地面反投影）")
        return
    print("\n── 反投影 ──")
    for name, (sx, sy) in pts.items():
        p = unproject(sx, sy, w, h, 0.0)
        if p is None:
            print(f"  {name}: ({sx}, {sy}) → 打不到地面")
            continue
        print(f"  {name:<12} 像素 ({sx:6.1f}, {sy:6.1f}) → 世界 ({p[0]:+7.3f}, 0, {p[2]:+7.3f})")


if __name__ == "__main__":
    main()

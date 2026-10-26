"""手动标出桌子的角点（像素），反投影成世界坐标 —— 这是最终定数的唯一可靠办法。

为什么不能靠颜色分割：桌子、椅子、画架、后墙柜子全是木色，
颜色分割会把它们连成一团（实测深 4.86 m，明显把椅子也算进来了）。

为什么不能靠「框对框」迭代：桌面在 y = 0.78、地面在 y = 0，
同一个屏幕像素投到这两个平面上的世界坐标**差很多**。
所以要标的是「**桌面的四个角**」，然后**只按 y = 0.78 那个平面**反投影。

用法：
    python room_marks.py            # 打印当前标注和结果
    （改 `MARKS` 里的像素值重跑；像素坐标从 g4_desk_crop.png 上读）
"""
import math

import numpy as np
from PIL import Image, ImageDraw

SRC = r"C:\Users\WY157\Desktop\GODOT\_arisu_captures\_fix1026\g3_desk.png"
DST = r"C:\Users\WY157\Desktop\GODOT\_arisu_captures\_fix1026\g6_marks.png"
CAM = np.array([1.20, 2.80, 6.80])
TARGET = np.array([2.00, 0.20, 2.20])
FOV_DEG = 60.0
UP = np.array([0.0, 1.0, 0.0])
DESK_TOP = 0.78

## 桌面四角（像素坐标，从 g3_desk.png 读）
## 顺序：西北(远左) / 东北(远右) / 东南(近右) / 西南(近左)
MARKS = {
    "NW": (1010, 392),
    "NE": (1200, 400),
    "SE": (1162, 592),
    "SW": (952, 578),
}


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
    im = Image.open(SRC).convert("RGB")
    w, h = im.size
    dr = ImageDraw.Draw(im)
    pts = {}
    print(f"桌面平面 y = {DESK_TOP} 上的反投影：")
    for name, (sx, sy) in MARKS.items():
        p = unproject(sx, sy, w, h, DESK_TOP)
        if p is None:
            print(f"  {name}: 打不到")
            continue
        pts[name] = (float(p[0]), float(p[2]))
        print(f"  {name:<3} 像素 ({sx:4d}, {sy:4d}) → 世界 x {p[0]:+7.3f}  z {p[2]:+7.3f}")
        dr.ellipse([sx - 7, sy - 7, sx + 7, sy + 7], outline=(0, 255, 0), width=3)
        dr.text((sx + 9, sy - 6), name, fill=(0, 255, 0))

    # 四边连起来，看是不是个矩形
    order = ["NW", "NE", "SE", "SW", "NW"]
    for i in range(4):
        if order[i] in MARKS and order[i + 1] in MARKS:
            dr.line([MARKS[order[i]], MARKS[order[i + 1]]], fill=(0, 255, 0), width=3)

    if len(pts) == 4:
        xs = [pts[k][0] for k in pts]
        zs = [pts[k][1] for k in pts]
        print(f"\n桌面水平范围：x {min(xs):+.3f} ~ {max(xs):+.3f}"
              f"（宽 {max(xs) - min(xs):.3f}）")
        print(f"                z {min(zs):+.3f} ~ {max(zs):+.3f}"
              f"（深 {max(zs) - min(zs):.3f}）")
        print(f"\n可直接用的碰撞盒（顶面 = 桌面 {DESK_TOP}）：")
        print(f"  中心 ({(min(xs) + max(xs)) / 2:.3f}, {DESK_TOP / 2:.3f}, "
              f"{(min(zs) + max(zs)) / 2:.3f})")
        print(f"  尺寸 ({max(xs) - min(xs):.3f}, {DESK_TOP:.3f}, {max(zs) - min(zs):.3f})")

    im.save(DST)
    print(f"\n已写 {DST}")
    crop = im.crop((850, 330, 1350, 700)).resize((1500, 1110), Image.LANCZOS)
    cp = DST.replace("g6_marks", "g6_crop")
    crop.save(cp)
    print(f"已写 {cp}")


if __name__ == "__main__":
    main()

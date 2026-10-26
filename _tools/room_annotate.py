"""把 `g3_desk.png` 里桌子附近裁出来放大，并叠上「世界坐标刻度线」，
方便人眼读数（也方便我下一步把碰撞盒坐标直接钉死）。

刻度线由 `room_measure.py` 里那套投影数学算出来 —— 已经用红方块验证过误差 1.6 px。
"""
import math

import numpy as np
from PIL import Image, ImageDraw

SRC = r"C:\Users\WY157\Desktop\GODOT\_arisu_captures\_fix1026\g3_desk.png"
DST = r"C:\Users\WY157\Desktop\GODOT\_arisu_captures\_fix1026\g4_annotated.png"
CAM = np.array([1.20, 2.80, 6.80])
TARGET = np.array([2.00, 0.20, 2.20])
FOV_DEG = 60.0
UP = np.array([0.0, 1.0, 0.0])


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


def main():
    im = Image.open(SRC).convert("RGB")
    w, h = im.size
    dr = ImageDraw.Draw(im)

    # 世界坐标刻度：x 与 z 各按 0.5 m 一条，画在**桌面高度 0.78** 上
    for x in np.arange(-1.0, 3.01, 0.5):
        p0 = project([x, 0.78, -1.5], w, h)
        p1 = project([x, 0.78, 5.0], w, h)
        if p0 and p1:
            major = abs(x - round(x)) < 0.01
            dr.line([p0, p1], fill=(0, 255, 255) if major else (0, 140, 140),
                    width=3 if major else 1)
            if major:
                dr.text((p0[0] + 4, p0[1] + 4), f"x{x:+.0f}", fill=(0, 255, 255))
    for z in np.arange(-1.5, 5.01, 0.5):
        p0 = project([-1.0, 0.78, z], w, h)
        p1 = project([3.0, 0.78, z], w, h)
        if p0 and p1:
            major = abs(z - round(z)) < 0.01
            dr.line([p0, p1], fill=(255, 160, 0) if major else (150, 90, 0),
                    width=3 if major else 1)
            if major:
                dr.text((p0[0] + 4, p0[1] - 14), f"z{z:+.0f}", fill=(255, 200, 0))

    # 老师锚点（已知 (1.80, 0, 2.60)）
    p = project([1.80, 0.02, 2.60], w, h)
    if p:
        dr.ellipse([p[0] - 10, p[1] - 10, p[0] + 10, p[1] + 10],
                   outline=(255, 0, 255), width=4)
        dr.text((p[0] + 14, p[1] - 6), "Sensei", fill=(255, 0, 255))

    im.save(DST)
    print(f"已写 {DST}")

    # 顺便裁一块桌子附近放大保存
    crop = im.crop((700, 250, 1600, 900)).resize((1800, 1300), Image.LANCZOS)
    crop_path = DST.replace("g4_annotated", "g4_desk_crop")
    crop.save(crop_path)
    print(f"已写 {crop_path}")


if __name__ == "__main__":
    main()

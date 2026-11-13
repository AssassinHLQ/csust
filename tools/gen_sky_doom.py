"""生成「末日风格」全景天空盒（等距圆柱 2:1，横向无缝可环绕）。

用途：第二关（长理校园）打完三只霸王龙之后，天换成末日 —— 见
`scripts/arena_lock.gd::_sky_doom()`。

为什么程序化生成而不是找素材：
  · 项目里现成的十张 AllSky 全景全是「好看的天」，没有末日感；
  · 直接找图有版权风险，尺寸/投影也不一定对；
  · 末日天要的就是**红黑乱流 + 低垂血日**，程序化正好够用，
    参数随时可以重跑调（本文件就是参数表）。

数学上必须注意：等距圆柱贴图在 u 方向首尾相接（2048 处接 0），
所以噪声**不能**用普通随机场（左右会有接缝），这里用「整数频率的正弦和」，
天然以 u∈[0,1) 为周期。

📌 第一版教训（已改）：
  · 加过一层「竖向裂痕」= 整数频率的 sin(kx·u)，结果整张天空是**等距竖条**
    （kx 是常数频率 → 条带、且贯通全高）—— 删掉，竖向细节交给云的 fBm；
  · 云只用 3 档频率、对比度不够 → 几乎看不见，天看起来只是"黄昏+栅格"；
    现在 6 档 fBm + smoothstep 拉对比 + 云缘受地平线红光照亮。

    python _tools/gen_sky_doom.py
"""
import math
import os

import numpy as np
from PIL import Image

W, H = 2048, 1024
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "_arisu_learn", "assets", "sky", "sky_doom.jpg")

# ── 配色 ──────────────────────────────────────────────────────────────
C_ZENITH = (0.018, 0.006, 0.012)     # 天顶：近黑的紫
C_UPPER = (0.075, 0.016, 0.024)      # 上层
C_HORIZON = (0.520, 0.078, 0.038)    # 地平线本体
C_HOT = (1.000, 0.300, 0.080)        # 地平线上那条炽热带
C_BELOW = (0.055, 0.014, 0.016)      # 地平线以下
C_NADIR = (0.010, 0.006, 0.006)
C_CLOUD = (0.016, 0.006, 0.010)      # 云体（遮挡用的近黑）
C_RIM = (0.90, 0.16, 0.06)           # 云缘被红光透出的边


def _fbm(u, v, seed=7, octaves=6, base_x=2, base_y=1, gain=0.52):
    """u∈[0,1) 周期、u/v 方向的 fBm。全部频率都是**整数**，所以横向无缝。"""
    rng = np.random.default_rng(seed)
    out = np.zeros_like(u)
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        kx = base_x * (2 ** o)
        ky = max(1, base_y * (2 ** o))
        ph1 = rng.uniform(0, 2 * math.pi)
        ph2 = rng.uniform(0, 2 * math.pi)
        ph3 = rng.uniform(0, 2 * math.pi)
        # 用两个方向的斜纹相加，避免「一层层横条」的观感
        out += amp * (0.60 * np.sin(2 * math.pi * kx * u + ph1) * np.cos(math.pi * ky * v + ph2)
                      + 0.40 * np.sin(2 * math.pi * (kx // 2 if kx > 2 else 1) * u + ph3)
                      * np.sin(math.pi * ky * v * 1.7 + ph1))
        total += amp
        amp *= gain
    return out / max(total, 1e-9)


def _norm(a):
    lo, hi = np.percentile(a, 2), np.percentile(a, 98)
    return np.clip((a - lo) / max(hi - lo, 1e-6), 0, 1)


def main():
    yi, xi = np.mgrid[0:H, 0:W].astype(np.float64)
    u = xi / W
    v = yi / H
    hz = 0.50

    # ── 1. 竖向渐变（三段的平滑插值）──
    def seg(t):
        return np.clip(t, 0, 1)[:, :, None]

    top = (np.array(C_ZENITH)[None, None, :] * (1 - seg(v / 0.28))
           + np.array(C_UPPER)[None, None, :] * seg(v / 0.28))
    mid = (np.array(C_UPPER)[None, None, :] * (1 - seg((v - 0.28) / 0.22))
           + np.array(C_HORIZON)[None, None, :] * seg((v - 0.28) / 0.22))
    low = (np.array(C_BELOW)[None, None, :] * (1 - seg((v - hz) / 0.16))
           + np.array(C_NADIR)[None, None, :] * seg((v - hz) / 0.16))
    img = np.where(v[:, :, None] < 0.28, top, np.where(v[:, :, None] < hz, mid, low))

    # 地平线炽热带：宽度受噪声调制，别做成一条完美直线
    wob = 0.020 + 0.014 * (_norm(_fbm(u, v, seed=3, octaves=3, base_x=4, base_y=2)) - 0.5) * 2.0
    hot = np.exp(-((v - hz) / wob) ** 2)[:, :, None] * np.array(C_HOT)[None, None, :]
    img = img + hot * 0.95

    # ── 2. 云：6 档 fBm，压出层次 ──
    c1 = _norm(_fbm(u, v, seed=11, octaves=6, base_x=2, base_y=1, gain=0.55))
    c2 = _norm(_fbm(u, v, seed=29, octaves=5, base_x=5, base_y=3, gain=0.50))
    dens = np.clip(0.68 * c1 + 0.32 * c2, 0, 1)
    # smoothstep 拉对比：中间调大幅压掉，只留团块和空隙
    dens = dens * dens * (3.0 - 2.0 * dens)
    dens = np.clip((dens - 0.34) / 0.56, 0, 1)
    # 只在「上层 → 地平线上方」浓；天顶留一点，天底压掉
    band = 0.35 + 0.95 * np.exp(-((v - 0.40) / 0.30) ** 2)
    band = band * np.clip((hz + 0.02 - v) / 0.06, 0, 1) + 0.0
    dens = np.clip(dens * band, 0, 1)

    # 云体：把天压暗（遮挡）
    img = img * (1.0 - 0.92 * dens[:, :, None]) \
        + np.array(C_CLOUD)[None, None, :] * (0.92 * dens[:, :, None])

    # 云缘受地平线红光：dens·(1-dens) 在中边缘最大
    rim = dens * (1.0 - dens) * 4.0
    rim = rim * np.exp(-((v - 0.44) / 0.26) ** 2) * 0.85
    img = img + rim[:, :, None] * np.array(C_RIM)[None, None, :]

    # 云的「底边」被更热的光从下方打亮（越靠地平线越强）
    under = np.clip(dens - 0.42, 0, 1) ** 1.5
    under = under * np.exp(-((v - 0.47) / 0.10) ** 2)
    img = img + under[:, :, None] * np.array((1.0, 0.42, 0.13))[None, None, :] * 0.9

    # ── 3. 低垂血日（u=0.68，地平线上方一点）──
    du = (u - 0.68)
    du = (du + 0.5) % 1.0 - 0.5
    dv = (v - 0.452) * 2.0
    r = np.sqrt((du * 2.0) ** 2 + dv ** 2)
    disc = np.clip((0.0165 - r) / 0.0165, 0, 1) ** 0.35
    glow1 = np.exp(-(r / 0.055) ** 2) * 0.9
    glow2 = np.exp(-(r / 0.16) ** 2) * 0.35
    img = img + disc[:, :, None] * np.array((1.0, 0.80, 0.46))[None, None, :] * 3.2
    img = img + (glow1 + glow2)[:, :, None] * np.array((1.0, 0.28, 0.08))[None, None, :]

    # ── 4. 收尾 ──
    rng = np.random.default_rng(97)
    img = img + rng.normal(0, 0.005, img.shape)
    img = np.power(np.clip(img, 0, 1), 0.90)

    arr = (np.clip(img, 0, 1) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(arr, "RGB").save(OUT, quality=92, subsampling=0)
    print("wrote %s  (%dx%d, %.0f KB)" % (OUT, W, H, os.path.getsize(OUT) / 1024.0))


if __name__ == "__main__":
    main()

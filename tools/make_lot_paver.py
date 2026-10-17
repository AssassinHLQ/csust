"""生成「空地」用的可平铺地砖贴图 + 法线图。

为什么程序生成：工程里没有任何地面贴图（`assets/` 只有 UI 和音效），
而外网素材要授权、要 `.import`、还要对口。地砖这种东西**程序画**最省事：
完全可平铺（四边接得上）、随时能调尺寸和脏污程度。

输出（`assets/tex/`）：
    lot_paver.png      512×512，2×2 块方砖，带灰缝 / 噪点 / 污渍
    lot_paver_n.png    同尺寸法线图（灰缝下凹，砖面微起伏）

用法（用工程自带的 python）：
    python tools/make_lot_paver.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets", "tex")
SIZE = 512
TILE = 2                 # 2×2 块砖
GROUT = 7                # 灰缝宽度（像素）
SEED = 20261018


def value_noise(size, cells, seed):
    """把 cells×cells 随机格点双线性放大 —— 够用的低频噪声，不用第三方库。"""
    rng = np.random.default_rng(seed)
    g = rng.random((cells, cells)).astype(np.float32)
    # 可平铺：最后一行/列抄第一行/列
    g[-1, :] = g[0, :]
    g[:, -1] = g[:, 0]
    small = Image.fromarray((g * 255).astype(np.uint8))
    return np.asarray(small.resize((size, size), Image.BICUBIC), dtype=np.float32) / 255.0


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(SEED)
    px = SIZE // TILE

    # ── 底色：每块砖一个微不同的灰 ──
    base = np.zeros((SIZE, SIZE), dtype=np.float32)
    for gy in range(TILE):
        for gx in range(TILE):
            v = 0.60 + float(rng.uniform(-0.045, 0.045))
            base[gy * px:(gy + 1) * px, gx * px:(gx + 1) * px] = v

    # ── 灰缝 ──
    grout = np.zeros((SIZE, SIZE), dtype=bool)
    for i in range(TILE + 1):
        c = i * px
        grout[max(0, c - GROUT // 2):c + GROUT // 2, :] = True
        grout[:, max(0, c - GROUT // 2):c + GROUT // 2] = True
    base[grout] = 0.40

    # ── 噪声：低频斑驳 + 高频颗粒 ──
    low = value_noise(SIZE, 6, SEED + 1) - 0.5
    mid = value_noise(SIZE, 24, SEED + 2) - 0.5
    fine = rng.normal(0.0, 0.022, (SIZE, SIZE)).astype(np.float32)
    base += low * 0.13 + mid * 0.07 + fine

    # ── 污渍：几团大一点的暗斑，画上去再模糊 ──
    stain = Image.new("L", (SIZE, SIZE), 0)
    d = ImageDraw.Draw(stain)
    for _ in range(9):
        r = int(rng.uniform(28, 90))
        x = int(rng.integers(0, SIZE))
        y = int(rng.integers(0, SIZE))
        d.ellipse([x - r, y - r, x + r, y + r], fill=int(rng.uniform(18, 46)))
    stain = stain.filter(ImageFilter.GaussianBlur(22))
    base -= np.asarray(stain, dtype=np.float32) / 255.0 * 0.16

    base = np.clip(base, 0.0, 1.0)
    # 偏冷一点点，跟场景的黄昏蓝调合（别做成暖水泥）
    rgb = np.stack([base * 0.97, base * 0.99, base * 1.02], axis=-1)
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))
    img.save(os.path.join(OUT, "lot_paver.png"))
    print("[paver] ->", os.path.join(OUT, "lot_paver.png"))

    # ── 法线图：从高度反推（灰缝下凹）──
    height = np.where(grout, 0.15, 1.0) + (mid * 0.25) + (fine * 2.0)
    height = height.astype(np.float32)
    hb = Image.fromarray((np.clip(height, 0, 1) * 255).astype(np.uint8))
    hb = hb.filter(ImageFilter.GaussianBlur(1.2))
    h = np.asarray(hb, dtype=np.float32) / 255.0
    # 可平铺的差分
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 2.6
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 2.6
    nz = np.ones_like(h)
    ln = np.sqrt(dx * dx + dy * dy + nz * nz)
    nrm = np.stack([-dx / ln, -dy / ln, nz / ln], axis=-1)
    nmap = Image.fromarray(((nrm * 0.5 + 0.5) * 255).astype(np.uint8))
    nmap.save(os.path.join(OUT, "lot_paver_n.png"))
    print("[paver] ->", os.path.join(OUT, "lot_paver_n.png"))
    print("[paver] 尺寸 %dx%d  砖 %dx%d  灰缝 %d px  均值 %.3f"
          % (SIZE, SIZE, TILE, TILE, GROUT, float(base.mean())))


main()

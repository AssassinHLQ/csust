"""把外部零件照片裁成配置单悬停区用的 492×560 深色底图。

用法：
    python tools/fit_part_photo.py 源图 输出.png [--cut-white] [--crop-bottom 像素]

统一做法（和现有 gpu/ram/ssd 那批一致）：
  · 等比缩放，最长边留 24 px 边距，居中；
  · 背景是上 30,28,26 → 下 22,20,19 的竖向渐变；
  · `--cut-white`：从四角泛洪抠掉纯白背景（商品图白底），银/白零件本体不受影响；
  · 带水印/广告条就 `--crop-bottom` 先裁掉一截。

⚠️ 源图都是第三方新闻/商品图，未授权；处理后的图只放本地，`.gitignore` 已排除，
   出处逐张记在 `assets/story/parts/SOURCES.md`。
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFilter

W, H = 492, 560
PAD = 24
TOP = (30, 28, 26)
BOTTOM = (22, 20, 19)


def gradient() -> Image.Image:
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / max(H - 1, 1)
        d.line([(0, y), (W, y)], fill=tuple(int(TOP[i] * (1 - t) + BOTTOM[i] * t) for i in range(3)))
    return img


def cut_white(im: Image.Image) -> Image.Image:
    """从四角泛洪，把连通的纯白背景标成透明，保留被轮廓包住的白色零件。"""
    rgba = im.convert("RGBA")
    w, h = rgba.size
    probe = rgba.convert("RGB").copy()
    seeds = [(x, 0) for x in range(0, w, 24)] + [(x, h - 1) for x in range(0, w, 24)]
    seeds += [(0, y) for y in range(0, h, 24)] + [(w - 1, y) for y in range(0, h, 24)]
    for xy in seeds:
        if probe.getpixel(xy) != (255, 0, 255):
            ImageDraw.floodfill(probe, xy, (255, 0, 255), thresh=30)
    px = probe.load()
    alpha = Image.new("L", (w, h), 255)
    ap = alpha.load()
    for y in range(h):
        for x in range(w):
            if px[x, y] == (255, 0, 255):
                ap[x, y] = 0
    # 白底商品图的边缘会留一圈白毛；先缩 1 px 再羽化
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.5))
    rgba.putalpha(alpha)
    return rgba


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--cut-white", action="store_true")
    ap.add_argument("--crop-bottom", type=int, default=0)
    args = ap.parse_args()

    im = Image.open(args.src)
    if args.crop_bottom > 0:
        im = im.crop((0, 0, im.width, im.height - args.crop_bottom))
    if args.cut_white:
        im = cut_white(im)
    else:
        im = im.convert("RGBA")

    scale = min((W - PAD * 2) / im.width, (H - PAD * 2) / im.height)
    im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))),
                   Image.LANCZOS)

    out = gradient().convert("RGBA")
    out.alpha_composite(im, ((W - im.width) // 2, (H - im.height) // 2))
    os.makedirs(os.path.dirname(os.path.abspath(args.dst)), exist_ok=True)
    out.convert("RGB").save(args.dst)
    print("WROTE", args.dst, out.size)


main()

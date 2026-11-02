"""从 Fusion Pixel 12px 里切出「游戏开发部楼梯→临时服务器据点」十四个字，供 3D 招牌与小指示牌。

为什么不用整份 6.7 MB 的 font.ttf：
  · 招牌/指示牌只需要十几个字，子集只有几 KB；
  · 招牌要求「真像素」：导入时必须 antialiasing=0、subpixel_positioning=0、
    generate_mipmaps=true，再让 Label3D 用 nearest 采样；整份字体是 UI 兜底字，
    这些设置不能全局改（小字号会变糙）。

用法：
    python tools/make_gamedev_sign_font.py
"""
import os

from fontTools import subset

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "ui", "font.ttf")
DST = os.path.join(ROOT, "assets", "ui", "gamedev_sign_12px.ttf")
TEXT = "游戏开发部楼梯→临时服务器据点"

opts = subset.Options()
opts.name_IDs = ["*"]          # 保留 OFL 许可字段
opts.name_languages = ["*"]
opts.notdef_outline = True
opts.layout_features = ["*"]

font = subset.load_font(SRC, opts)
subsetter = subset.Subsetter(options=opts)
subsetter.populate(text=TEXT)
subsetter.subset(font)
font.save(DST)
print("WROTE", DST, os.path.getsize(DST), "bytes")

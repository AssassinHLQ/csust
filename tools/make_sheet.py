"""把 _shots/*.png 拼成一张 24 格动作总览，方便一眼核对导入结果。"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = r"C:\Users\WY157\Desktop\GODOT\_arisu_captures"
SHOTS = ROOT
OUT = os.path.join(SHOTS, "_总览.png")

COLS, ROWS = 6, 4
TILE_W, TILE_H = 360, 252
CROP = (330, 260, 850, 624)          # 角色所在区域
LABEL_H = 22
BG = (18, 20, 26)
FG = (232, 236, 244)

files = sorted(f for f in os.listdir(SHOTS) if f.endswith(".png") and not f.startswith("_"))
assert len(files) == 24, len(files)

try:
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 15)
except OSError:
    font = ImageFont.load_default()

W = COLS * TILE_W
H = ROWS * (TILE_H + LABEL_H)
sheet = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(sheet)

for i, fn in enumerate(files):
    img = Image.open(os.path.join(SHOTS, fn)).convert("RGB").crop(CROP)
    img = img.resize((TILE_W, TILE_H), Image.LANCZOS)
    cx = (i % COLS) * TILE_W
    cy = (i // COLS) * (TILE_H + LABEL_H)
    sheet.paste(img, (cx, cy))
    draw.rectangle([cx, cy + TILE_H, cx + TILE_W - 1, cy + TILE_H + LABEL_H - 1], fill=(28, 31, 40))
    name = fn.split("_", 1)[1].rsplit(".", 1)[0]
    draw.text((cx + 8, cy + TILE_H + 3), name, fill=FG, font=font)
    draw.rectangle([cx, cy, cx + TILE_W - 1, cy + TILE_H + LABEL_H - 1], outline=(58, 63, 78))

sheet.save(OUT)
print("saved", OUT, sheet.size)

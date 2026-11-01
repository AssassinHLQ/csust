# -*- coding: utf-8 -*-
"""柴关电脑城 · 配置单插图生成器

一次生成两张（剧情里店员先拿 B300 忽悠、小桃拆台后换成 5090）：

    assets/story/config_sheet.png        B300 八卡整机（¥520 万）
    assets/story/config_sheet_5090.png   八卡 5090 工作站（¥50 万）

为什么用 Pillow 排而不是直接让 AI 画：
  AI 画中文字会糊成乱码，型号 / 价格又必须准确，所以
  **照片交给 AI 或网络图，文字交给这里排**。

用法：
    python tools/make_config_sheet.py

依赖：Pillow、微软雅黑（C:/Windows/Fonts/msyh*.ttc）。
右侧照片的出处见 assets/story/parts/SOURCES.md 与 CREDITS.md。
"""

import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORY = os.path.join(ROOT, "assets", "story")

W, H = 1600, 970
PAPER = (242, 228, 201)
INK = (46, 36, 28)
INK_SOFT = (98, 82, 66)
ACCENT = (183, 51, 36)
HILITE = (250, 238, 206)
LINE = (198, 175, 141)

BOLD = r"C:\Windows\Fonts\msyhbd.ttc"
REG = r"C:\Windows\Fonts\msyh.ttc"

COL_PART = 48
COL_MODEL = 168
COL_QTY = 868
COL_PRICE = 1016
Y0 = 146
RH = 66

PHOTO_X, PHOTO_Y, PHOTO_W, PHOTO_H = 1064, 146, 492, 560


def font(path, size):
    return ImageFont.truetype(path, size, index=0)


SHEETS = [
    {
        "out": "config_sheet.png",
        "subtitle": "2026.11 / 数据中心级 / 店员推荐",
        "rows": [
            ("显卡", "NVIDIA B300（Blackwell Ultra）· 288GB HBM3E · NVLink 5", "8", "¥40 万/张", True),
            ("整机", "HGX B300 八卡基板 + 8U 机箱 · 冷板液冷", "1", "¥60 万", False),
            ("处理器", "Intel Xeon 6 6980P · 128 核 · 500W", "2", "¥9 万/颗", False),
            ("内存", "DDR5-6400 ECC RDIMM 64GB · 24 通道 = 1.5TB", "24", "¥0.7 万/条", True),
            ("系统盘", "PCIe 5.0 NVMe 1.92TB · RAID 1", "2", "¥0.3 万", False),
            ("数据盘", "PCIe 5.0 NVMe 7.68TB · RAID 10", "8", "¥1 万", False),
            ("网络", "ConnectX-8 800G · InfiniBand", "8", "¥4 万", False),
            ("液冷", "机架式 CDU + 冷板 · ≥ 60 kW", "1", "¥50 万", False),
            ("配电", "12kW 电源框 · 2N 冗余", "1", "¥20 万", False),
        ],
        "total": "≈ ¥520 万",
        "total_note": "约 12 kW · 一个 42U 机柜 · 不含机房改造",
        "photo": os.path.join(STORY, "hero_b300.png"),
        "photo_crop": None,
        "pills": [("8 × B300 288GB", True), ("24 × 64GB ECC = 1.5TB", False)],
        "caption": "图上为八卡计算托盘：8 颗 B300 + 24 条 ECC 内存",
        "footer": "※ 价格为 2026 年 11 月渠道估算，随行情波动；整机不含机房改造与安装。",
    },
    {
        "out": "config_sheet_5090.png",
        "subtitle": "2026.11 / 八卡 5090 / 小桃改单",
        "rows": [
            ("显卡", "NVIDIA RTX 5090 · 32GB GDDR7 · 575W", "8", "¥5.5 万/张", True),
            ("整机", "WRX90 工作站主板 + 开放式机架", "1", "¥2.5 万", False),
            ("处理器", "Threadripper PRO 9995WX · 96 核 · 128 条 PCIe 5.0", "1", "¥10 万", False),
            ("内存", "DDR5-5600 ECC 32GB · 8 条 = 256GB", "8", "¥0.4 万/条", True),
            ("系统盘", "PCIe 5.0 NVMe 2TB · RAID 1", "2", "¥0.3 万", False),
            ("数据盘", "PCIe 5.0 NVMe 8TB · RAID 0", "4", "¥1.2 万", False),
            ("电源", "2000W ATX 3.1 · 2N 冗余", "2", "¥0.4 万", False),
            ("散热", "开放式机架 + 工业扇", "1", "¥0.3 万", False),
            ("显示器", "27 英寸 4K 160Hz", "2", "¥0.4 万", False),
        ],
        "total": "≈ ¥67 万",
        "total_note": "约 5 kW · 一张工位 · 能装能跑还能打游戏",
        "photo": os.path.join(STORY, "parts", "hero_5090.png"),
        "photo_crop": (0, 0, 1023, 620),   # 裁掉右下角的水印
        "pills": [("8 × RTX 5090 32GB", True), ("256GB ECC = 8 × 32GB", False)],
        "caption": "图上为八卡 5090 工作站：8 张显卡 + 8 条 ECC 内存",
        "footer": "※ 八张 5090 的钱，只够买一张半 B300。",
    },
]


def split_model(text):
    if "·" in text:
        a, b = text.split("·", 1)
        return a.strip(), "·" + b.strip()
    return text, ""


def render(spec):
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)

    for y in range(0, H, 3):
        d.line([(0, y), (W, y)], fill=(238, 224, 197))
    d.rectangle([0, 0, W - 1, H - 1], outline=LINE, width=2)
    d.rectangle([10, 10, W - 11, H - 11], outline=(214, 192, 158), width=1)

    d.text((48, 34), "柴关电脑城 · 装机配置单", font=font(BOLD, 42), fill=INK)
    d.text((50, 92), spec["subtitle"], font=font(REG, 20), fill=INK_SOFT)
    d.line([(48, 126), (1032, 126)], fill=ACCENT, width=3)

    f_part = font(BOLD, 23)
    f_model = font(REG, 21)
    f_spec = font(REG, 18)
    f_qty = font(BOLD, 25)
    f_price = font(REG, 21)

    for i, (part, model, qty, price, hot) in enumerate(spec["rows"]):
        y = Y0 + i * RH
        if hot:
            d.rounded_rectangle([40, y - 6, 1032, y + RH - 10], radius=8, fill=HILITE,
                                outline=(228, 190, 118), width=2)
        elif i % 2 == 1:
            d.rectangle([40, y - 6, 1032, y + RH - 10], fill=(237, 223, 196))
        d.text((COL_PART, y + 2), part, font=f_part, fill=ACCENT if hot else INK)
        m1, m2 = split_model(model)
        d.text((COL_MODEL, y), m1, font=f_model, fill=INK)
        d.text((COL_MODEL, y + 28), m2, font=f_spec, fill=INK_SOFT)
        if qty != "—":
            qt = "×" + qty
            qw = d.textlength(qt, font=f_qty)
            d.text((COL_QTY - qw, y + 4), qt, font=f_qty, fill=INK)
        tw = d.textlength(price, font=f_price)
        d.text((COL_PRICE - tw, y + 6), price, font=f_price, fill=INK)
        d.line([(48, y + RH - 12), (1032, y + RH - 12)], fill=LINE, width=1)

    ty = Y0 + len(spec["rows"]) * RH + 6
    d.rounded_rectangle([40, ty, 1032, ty + 96], radius=10, fill=(58, 44, 34))
    d.text((66, ty + 10), "整机合计", font=font(BOLD, 26), fill=(238, 222, 190))
    d.text((66, ty + 48), spec["total_note"], font=font(REG, 19), fill=(206, 186, 156))
    tw = d.textlength(spec["total"], font=font(BOLD, 46))
    d.text((1010 - tw, ty + 20), spec["total"], font=font(BOLD, 46), fill=(255, 216, 120))

    ph = Image.open(spec["photo"]).convert("RGB")
    if spec["photo_crop"]:
        ph = ph.crop(spec["photo_crop"])
    scale = max(PHOTO_W / ph.width, PHOTO_H / ph.height)
    ph = ph.resize((max(PHOTO_W, int(ph.width * scale)),
                    max(PHOTO_H, int(ph.height * scale))), Image.LANCZOS)
    left = (ph.width - PHOTO_W) // 2
    top = (ph.height - PHOTO_H) // 2
    ph = ph.crop((left, top, left + PHOTO_W, top + PHOTO_H))

    mask = Image.new("L", (PHOTO_W, PHOTO_H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, PHOTO_W - 1, PHOTO_H - 1], radius=14, fill=255)
    img.paste(ph, (PHOTO_X, PHOTO_Y), mask)
    d.rounded_rectangle([PHOTO_X, PHOTO_Y, PHOTO_X + PHOTO_W, PHOTO_Y + PHOTO_H],
                        radius=14, outline=(120, 96, 72), width=2)

    def pill(y, text, filled):
        f = font(BOLD, 26)
        tw2 = d.textlength(text, font=f)
        pw, phh = tw2 + 44, 54
        x = PHOTO_X + 18
        if filled:
            d.rounded_rectangle([x, y, x + pw, y + phh], radius=27, fill=(183, 51, 36))
            d.text((x + 22, y + 10), text, font=f, fill=(255, 245, 230))
        else:
            d.rounded_rectangle([x, y, x + pw, y + phh], radius=27, fill=(36, 30, 26))
            d.text((x + 22, y + 10), text, font=f, fill=(255, 216, 120))

    a, b = spec["pills"]
    pill(PHOTO_Y + 18, a[0], a[1])
    pill(PHOTO_Y + PHOTO_H - 74, b[0], b[1])

    d.text((PHOTO_X, PHOTO_Y + PHOTO_H + 16), spec["caption"],
           font=font(REG, 18), fill=INK_SOFT)
    d.text((48, H - 52), spec["footer"], font=font(REG, 17), fill=(150, 126, 98))
    d.text((48, H - 28), "柴关电脑城 · 本单一经售出，不退不换[TVT]",
           font=font(BOLD, 17), fill=(150, 96, 70))

    out = os.path.join(STORY, spec["out"])
    img.save(out, "PNG")
    print("WROTE", out, os.path.getsize(out))


if __name__ == "__main__":
    for s in SHEETS:
        render(s)

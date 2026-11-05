#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""archviz 贴图瘦身：把 3ds Max 那套「8000×3000 的 JPG」压到游戏能吃的尺寸。

为什么必须做（本项目实测，2026-11-06）：

    爱给网「现代网咖·电竞酒店」那套贴图：108 张可读尺寸，**1.05 亿像素**。
    全分辨率按 RGBA8 进显存 = **400 MB**，带 mipmap = **533 MB**。
    其中单张 `JS026.jpg` 就是 **8014×3069** —— 一张图 98 MB。

    而 Godot 默认**不会**帮你缩：`max_width/max_height = 0` 表示「原样」。
    于是这套贴图光是自己就能把 8 GB 卡吃掉 5%。

做法：
  · 按用途给不同上限（`--cap` 统一给，或用下面的表默认）
  · 输出到独立目录，**不动原图**（原图留着重新导）
  · 顺手报「缩完能省多少显存」

用法：
    python _tools/opt_archviz_textures.py <输入目录> <输出目录>
    python _tools/opt_archviz_textures.py in/ out/ --cap=2048
    python _tools/opt_archviz_textures.py in/ out/ --dry-run

⚠️ 这个脚本只缩尺寸、不转格式（Godot 那边用「VRAM 压缩」导入模式再做 BC1/BC7，
   那一步能把 0.5~1 B/px 的收益拿到手，比在这里存 PNG/JPG 划算得多）。
"""
import argparse
import os
import sys

try:
    from PIL import Image
except ImportError:
    print("!! 需要 Pillow：pip install Pillow", file=sys.stderr)
    sys.exit(2)

# 单张贴图的像素上限。超过这个就等比缩。
DEFAULT_CAP = 2048
# 这些名字像「法线 / bump / roughness / mask」的，可以给更低的上限
LOW_DETAIL_HINTS = ("bump", "normal", "rough", "metal", "ao", "mask", "spec", "gloss")

# 读得出来、也值得重新存的格式
EXTS = (".jpg", ".jpeg", ".png", ".bmp", ".tga", ".tif", ".tiff", ".webp")


def human_mb(n):
    return "%.1f MB" % (n / 1048576.0)


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--cap", type=int, default=DEFAULT_CAP,
                    help="单边像素上限（默认 %d）" % DEFAULT_CAP)
    ap.add_argument("--low-cap", type=int, default=1024,
                    help="法线/粗糙度这类贴图的上限（默认 1024）")
    ap.add_argument("--quality", type=int, default=88, help="JPEG 质量（默认 88）")
    ap.add_argument("--dry-run", action="store_true", help="只报账，不写文件")
    args = ap.parse_args()

    if not os.path.isdir(args.src):
        print("!! 输入目录不存在：%s" % args.src, file=sys.stderr)
        return 2
    if not args.dry_run:
        os.makedirs(args.dst, exist_ok=True)

    total_before_px = 0
    total_after_px = 0
    done = 0
    skipped = 0
    failed = []

    print("%-40s %13s -> %-13s %s" % ("文件", "原尺寸", "缩后", "说明"))
    print("-" * 96)

    for name in sorted(os.listdir(args.src)):
        low = name.lower()
        if not low.endswith(EXTS):
            continue
        path = os.path.join(args.src, name)
        try:
            with Image.open(path) as im:
                w, h = im.size
                cap = args.low_cap if any(k in low for k in LOW_DETAIL_HINTS) else args.cap
                scale = min(1.0, cap / float(max(w, h)))
                nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
                total_before_px += w * h
                total_after_px += nw * nh

                note = ""
                if scale < 1.0:
                    note = "缩到 %.0f%%" % (scale * 100.0)
                else:
                    note = "原样"

                print("%-40s %6dx%-6d -> %5dx%-6d %s" % (
                    name[:40], w, h, nw, nh, note))

                if args.dry_run:
                    skipped += 1
                    continue

                if scale < 1.0:
                    im = im.resize((nw, nh), Image.LANCZOS)
                # 输出统一成「无 alpha 就 JPEG、有 alpha 就 PNG」，别把 2 MB 的 BMP 带进去
                out_name = os.path.splitext(name)[0]
                has_alpha = im.mode in ("RGBA", "LA", "P") and "transparency" in im.info
                if im.mode == "P":
                    im = im.convert("RGBA" if has_alpha else "RGB")
                if im.mode not in ("RGB", "RGBA", "L"):
                    im = im.convert("RGBA" if has_alpha else "RGB")

                if has_alpha:
                    out = os.path.join(args.dst, out_name + ".png")
                    im.save(out, "PNG", optimize=True)
                else:
                    if im.mode != "RGB":
                        im = im.convert("RGB")
                    out = os.path.join(args.dst, out_name + ".jpg")
                    im.save(out, "JPEG", quality=args.quality, optimize=True,
                            progressive=True)
                done += 1
        except Exception as e:  # noqa: BLE001 - 单张失败不该中断整批
            failed.append((name, str(e)))

    print("-" * 96)
    print("像素总数：%.1f M -> %.1f M（缩到 %.0f%%）" % (
        total_before_px / 1e6, total_after_px / 1e6,
        100.0 * total_after_px / max(total_before_px, 1)))
    print("RGBA8 显存（不含 mip） ：%s -> %s" % (
        human_mb(total_before_px * 4), human_mb(total_after_px * 4)))
    print("含 mipmap（×1.33）    ：%s -> %s" % (
        human_mb(total_before_px * 4 * 1.333), human_mb(total_after_px * 4 * 1.333)))
    print("再叠 VRAM 压缩 BC1(0.5B/px) 的粗略下限：%s" % (
        human_mb(total_after_px * 0.5 * 1.333)))
    print("处理 %d 张，跳过 %d，失败 %d" % (done, skipped, len(failed)))
    for n, e in failed[:10]:
        print("  ✗ %s: %s" % (n, e))
    if args.dry_run:
        print("\n（--dry-run：没有写任何文件）")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""给一个 `.glb` 的 `.import` 文件打补丁：修单位、省顶点内存、开 VRAM 压缩。

背景（本项目实测，2026-11-06，爱给网「现代网咖·电竞酒店」）：

    · 3ds Max 导出的 FBX 单位是**厘米**，Blender 转 GLB 之后 Godot 按
      「1 单位 = 1 米」读 ⇒ 包围盒 7814 × 4122 × 7684 m（7.8 公里）。
      正确做法不是在代码里 `scale = 0.01`，而是**导入时就修**：
      `nodes/root_scale = 0.01`，这样场景里拿到的就是正确尺寸的模型。

    · `meshes/ensure_tangents = true` 让每个顶点多存**16 字节**切线。
      2,709,373 顶点 × 16 B ≈ **41 MB**，而只有用**法线贴图**才需要切线。
      纯色/只有 albedo 的模型可以关掉。

    · 贴图默认 `compress/mode` = 0（Lossless，等于不压，4 B/px）。
      那套贴图 32.4 M 像素 → **124 MB**（带 mip 165 MB）。
      改成 VRAM 压缩（BC1/BC3/BC7）能到 **1/4 ~ 1/8**。

用法：

    # 只体检：打印现在是什么、建议改什么
    python _tools/patch_glb_import.py models/xxx.glb --report

    # 真改（会先备份成 .import.bak）
    python _tools/patch_glb_import.py models/xxx.glb --apply --root-scale=0.01

    # 只想改一项
    python _tools/patch_glb_import.py models/xxx.glb --apply --no-tangents
    python _tools/patch_glb_import.py models/xxx.glb --apply --vram-compress

⚠️ 改完要在 Godot 里重新导入（`--headless --import`），否则不生效。
⚠️ `--vram-compress` 对**法线贴图**会选成 BC5/RGBA（Godot 自己按用途判），
   对**带 alpha** 的会选 BC3/BC7。这一步没法在 `.import` 里逐张指定，
   所以这里改的是「默认压缩模式」，让 Godot 按贴图用途自己挑。
"""

import argparse
import os
import re
import shutil
import sys

# Godot 的 compress/mode 整数值
COMPRESS_LOSSLESS = 0
COMPRESS_LOSSY = 1
COMPRESS_VRAM = 2


def read_params(path):
    """把 [params] 段读成 dict（值保留原始字符串）。"""
    out = {}
    inside = False
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            s = line.rstrip("\n")
            if s.startswith("[") and s.endswith("]"):
                inside = (s == "[params]")
                continue
            if inside and "=" in s:
                k, v = s.split("=", 1)
                out[k.strip()] = v.strip()
    return out


def patch(path, updates):
    """把 updates 里的键值写进 [params] 段（有则替换、无则追加）。"""
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()

    changed = []
    for key, val in updates.items():
        # 只处理 [params] 段里的行
        pat = re.compile(r"^(" + re.escape(key) + r")\s*=\s*.*$", re.M)
        if pat.search(text):
            old = pat.search(text).group(0)
            if old.strip() != "%s=%s" % (key, val):
                text = pat.sub("%s=%s" % (key, val), text, count=1)
                changed.append((key, old.split("=", 1)[1].strip(), val))
        else:
            # 追加到 [params] 段末尾（找下一个 [section] 或文件尾）
            m = re.search(r"^\[params\]\s*$", text, re.M)
            if not m:
                print("!! 没有 [params] 段：%s" % path, file=sys.stderr)
                return changed
            start = m.end()
            nxt = re.search(r"^\[", text[start:], re.M)
            insert_at = start + nxt.start() if nxt else len(text)
            text = text[:insert_at] + "%s=%s\n" % (key, val) + text[insert_at:]
            changed.append((key, "<无>", val))

    if changed:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    return changed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("glb", help=".glb / .gltf 路径")
    ap.add_argument("--apply", action="store_true", help="真的写入（否则只报告）")
    ap.add_argument("--root-scale", type=float, default=None,
                    help="导入时的根缩放（修单位用；厘米建模给 0.01）")
    ap.add_argument("--no-tangents", action="store_true",
                    help="关掉 ensure_tangents（没有法线贴图时省 16 B/顶点）")
    ap.add_argument("--vram-compress", action="store_true",
                    help="贴图走 VRAM 压缩（gltf/embedded_image_handling=2 = Basis Universal）")
    ap.add_argument("--texture-handling", type=int, default=None,
                    choices=[0, 1, 2, 3],
                    help="直接指定 gltf/embedded_image_handling："
                         "0=丢弃 1=提取到文件(默认) 2=Basis Universal(VRAM压缩) 3=未压缩内嵌")
    ap.add_argument("--no-lods", action="store_true",
                    help="关掉自动生成 LOD（本来默认是开的，别乱关）")
    args = ap.parse_args()

    imp = args.glb + ".import"
    if not os.path.exists(imp):
        print("!! 找不到 %s（先用 Godot 导入一次）" % imp, file=sys.stderr)
        return 2

    params = read_params(imp)
    print("=== 现状：%s ===" % os.path.basename(imp))
    for k in ["nodes/root_scale", "nodes/apply_root_scale", "meshes/ensure_tangents",
              "meshes/generate_lods", "gltf/embedded_image_handling"]:
        print("  %-34s = %s" % (k, params.get(k, "<无>")))

    updates = {}
    if args.root_scale is not None:
        updates["nodes/root_scale"] = repr(float(args.root_scale))
        updates["nodes/apply_root_scale"] = "true"
    if args.no_tangents:
        updates["meshes/ensure_tangents"] = "false"
    if args.texture_handling is not None:
        updates["gltf/embedded_image_handling"] = str(int(args.texture_handling))
    elif args.vram_compress:
        # Godot 4 的 GLTF 贴图处理档位：
        #   0 = 丢弃 / 1 = 提取到文件（默认，**不压缩**，4 B/px）
        #   2 = **Basis Universal（VRAM 压缩）** ← 就是这个
        #   3 = 未压缩内嵌
        updates["gltf/embedded_image_handling"] = "2"
    if args.no_lods:
        updates["meshes/generate_lods"] = "false"

    if not updates:
        print("\n（没有要改的；用 --root-scale / --no-tangents 指定）")
        return 0

    print("\n=== 将要改成 ===")
    for k, v in updates.items():
        print("  %-34s %s → %s" % (k, params.get(k, "<无>"), v))

    if not args.apply:
        print("\n（--report 模式，没有写入；加 --apply 才生效）")
        return 0

    bak = imp + ".bak"
    if not os.path.exists(bak):
        shutil.copy2(imp, bak)
        print("\n已备份 → %s" % bak)

    changed = patch(imp, updates)
    for k, old, new in changed:
        print("  ✓ %-34s %s → %s" % (k, old, new))
    print("\n改完了。重新导入：")
    print('  Godot_...console.exe --path . --headless --import')
    return 0


if __name__ == "__main__":
    sys.exit(main())

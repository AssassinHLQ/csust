# -*- coding: utf-8 -*-
"""体检报告：导入一个模型，列出「三角数都堆在哪」+ 材质/贴图负担。

为什么要单独一个：`opt_archviz.py --report` 只给总量，判断「该不该减面」
需要**分布** —— 是「一个 300 万面的大沙发」还是「800 个 1 万面的小零件」，
两者的处理方式完全相反。

用法：
    blender -b -P _tools/inspect_archviz.py -- --in room.fbx [--top=25]
"""

import argparse
import os
import sys

import bpy


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--top", type=int, default=25)
    return ap.parse_args(argv)


def import_model(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=True)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    else:
        raise SystemExit("不认识的格式：%s" % ext)


def main():
    a = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    print("[inspect] 导入 %s" % a.src)
    import_model(a.src)

    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    rows = []
    total = 0
    for o in objs:
        me = o.data
        me.calc_loop_triangles()
        t = len(me.loop_triangles)
        total += t
        rows.append({
            "name": o.name,
            "tri": t,
            "slots": len(o.material_slots),
            "mats": [s.material.name if s.material else "-" for s in o.material_slots],
        })

    print("[inspect] 物件 %d | 三角 %d | 材质槽合计 %d"
          % (len(rows), total, sum(r["slots"] for r in rows)))

    # ── 三角分布：累计占比 ──
    rows.sort(key=lambda r: -r["tri"])
    print("[inspect]")
    print("[inspect] === 最重的物件（前 %d）===" % a.top)
    print("[inspect] %-40s %10s %6s  %s" % ("名称", "三角", "材质槽", "累计%"))
    acc = 0
    for r in rows[:a.top]:
        acc += r["tri"]
        print("[inspect] %-40s %10d %6d  %5.1f%%"
              % (r["name"][:40], r["tri"], r["slots"], 100.0 * acc / max(total, 1)))

    # ── 按大小分桶：判断该减面还是该删 ──
    print("[inspect]")
    print("[inspect] === 三角数分布 ===")
    buckets = [(0, 100), (100, 1000), (1000, 10000), (10000, 100000), (100000, 10**9)]
    for lo, hi in buckets:
        sel = [r for r in rows if lo <= r["tri"] < hi]
        if not sel:
            continue
        s = sum(r["tri"] for r in sel)
        print("[inspect]   %6d~%-8d %5d 个物件, %9d 三角 (%4.1f%%)"
              % (lo, hi, len(sel), s, 100.0 * s / max(total, 1)))

    # ── 材质清单（决定贴图负担）──
    mats = {}
    for r in rows:
        for m in r["mats"]:
            mats[m] = mats.get(m, 0) + 1
    print("[inspect]")
    print("[inspect] === 材质 %d 个，用得最多的前 15 ===" % len(mats))
    for name, n in sorted(mats.items(), key=lambda kv: -kv[1])[:15]:
        print("[inspect]   ×%-4d %s" % (n, name[:60]))

    # ── 贴图：尺寸与实际像素负担 ──
    imgs = [i for i in bpy.data.images if i.size[0] > 0]
    tot_px = 0
    print("[inspect]")
    print("[inspect] === 贴图 %d 张 ===" % len(imgs))
    for i in sorted(imgs, key=lambda x: -(x.size[0] * x.size[1]))[:15]:
        px = i.size[0] * i.size[1]
        tot_px += px
        print("[inspect]   %-32s %5dx%-5d  %6.1f MB(未压)"
              % (os.path.basename(i.filepath or i.name)[:32],
                 i.size[0], i.size[1], px * 4 / 1048576.0))
    # 没在上面列出的也要计入总像素
    listed = {id(i) for i in sorted(imgs, key=lambda x: -(x.size[0] * x.size[1]))[:15]}
    for i in imgs:
        if id(i) not in listed:
            tot_px += i.size[0] * i.size[1]
    print("[inspect] 合计像素 %.1f M → 全分辨率 RGBA8 约 %.0f MB（含 mip 约 %.0f MB）"
          % (tot_px / 1e6, tot_px * 4 / 1048576.0, tot_px * 4 * 1.333 / 1048576.0))


if __name__ == "__main__":
    main()

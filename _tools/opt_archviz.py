# -*- coding: utf-8 -*-
"""archviz 模型优化（Blender 5.x）：FBX/OBJ/GLB 进，优化后的 GLB 出。

为什么需要这一步（本项目实测，2026-11-06）：

    现有电竞房 `scenes/esports_room.tscn`：
        385 个网格节点 / 339 个唯一 Mesh / **499 个表面** / **只有 24 个材质**
        → 按材质合并的**上限**是 499 个 draw call 降到 24 个（少 20 倍）

    爱给网那套「现代网咖·电竞酒店」是典型的 3ds Max 建筑可视化导出：一个房间拆成
    几百上千个独立物件（每把椅子、每台显示器、每根线都是独立 Mesh）。这种数据进
    Godot 之后，**面数往往不是瓶颈，draw call 才是** —— 每个独立物件至少一次提交。

本脚本干四件事（每一步都能单独关）：

  1. **按材质合并**（`--merge=material`，默认）：把所有用同一材质的网格 join 成一个。
     这是对过 draw call 最有效的一刀，且**不改任何几何和贴图**。
     也可以 `--merge=none`（不动）或 `--merge=all`（全合成一个，最省但没法单独动）。
  2. **可选减面**（`--decimate=0.5`）：按三角数比例抽稀。建筑可视化常带几十万面的
     小五金件，肉眼看不出，但别对「主体轮廓」用太狠。
  3. **去掉极小的物件**（`--min-size=0.01`，单位米）：尺寸小于这个的物件多半是
     拉丝/卡扣，玩家永远看不清，直接删比减面划算。
  4. **导出 GLB**：`--export`，并打印最终统计。

用法：

    # 先只体检，不改任何东西
    blender -b -P _tools/opt_archviz.py -- --in room.fbx --report

    # 真跑：按材质合并 + 1024 以下小件删掉
    blender -b -P _tools/opt_archviz.py -- \
        --in room.fbx --out room_opt.glb --merge=material --min-size=0.01

    # 再加减面
    blender -b -P _tools/opt_archviz.py -- \
        --in room.fbx --out room_opt.glb --decimate=0.6

⚠️ 本脚本**不改贴图**。贴图瘦身走 `opt_archviz_textures.py`，
   VRAM 压缩走 Godot 导入设置（见 MEMORY §19 / docs）。
⚠️ `--merge=material` 之后每个材质只剩一个物件，**不能再单独移动/隐藏**其中一部分。
   静态房间没问题；要动画的物件请先挑出来（`--keep-animated`）。
"""

import argparse
import os
import sys

import bpy
from mathutils import Vector


# ---------------------------------------------------------------- 参数

def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    ap = argparse.ArgumentParser(prog="opt_archviz")
    ap.add_argument("--in", dest="src", required=True, help="输入模型（fbx/obj/glb/gltf）")
    ap.add_argument("--out", dest="dst", default="", help="输出 .glb")
    ap.add_argument("--merge", default="material",
                    choices=["none", "material", "all"],
                    help="合并策略（默认 material）")
    ap.add_argument("--decimate", type=float, default=0.0,
                    help="统一减面比例 0~1，0=不减（默认 0）")
    ap.add_argument("--decimate-adaptive", action="store_true",
                    help="自适应减面：按每个物件自己的三角数决定减多狠（装饰大件砍很、"
                         "墙地板不动）。比 --decimate 合理得多。")
    ap.add_argument("--decimate-safety", type=float, default=1.0,
                    help="自适应减面的力度系数：<1 更狠，>1 更保守（默认 1.0）")
    ap.add_argument("--no-merge", action="store_true",
                    help="同 --merge=none（方便记忆）")
    ap.add_argument("--texture-cap", type=int, default=0,
                    help="导出前把贴图最大边缩到这个像素数（0=不动；建议 1024~2048）。"
                         "GLB 是内嵌贴图的，导出之后就没法在 Godot 里批量改了。")
    ap.add_argument("--min-size", type=float, default=0.0,
                    help="删掉最大边小于这个值的物件（米），0=不删")
    ap.add_argument("--report", action="store_true", help="只体检，不导出")
    ap.add_argument("--keep-animated", action="store_true",
                    help="带父子/动画/形态键的物件不参与合并")
    return ap.parse_args(argv)


# ---------------------------------------------------------------- 清理

def wipe_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_model(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=True)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=path)
    else:
        raise SystemExit("不认识的格式：%s" % ext)


# ---------------------------------------------------------------- 统计

def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def tri_count(obj):
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def report(tag):
    objs = mesh_objects()
    tris = sum(tri_count(o) for o in objs)
    # 「表面数」≈ 每个物件的 material slot 数，也就是 Godot 那边 draw call 的下限
    surfaces = 0
    mats = set()
    for o in objs:
        for slot in o.material_slots:
            surfaces += 1
            if slot.material:
                mats.add(slot.material.name)
    print("[archviz] %-14s 物件 %5d | 三角 %10d | 表面(≈draw call) %5d | 材质 %4d"
          % (tag, len(objs), tris, surfaces, len(mats)))
    return {"objs": len(objs), "tris": tris, "surfaces": surfaces, "mats": len(mats)}


# ---------------------------------------------------------------- 优化

def drop_tiny(min_size):
    if min_size <= 0.0:
        return 0
    victims = []
    for o in mesh_objects():
        # 物件自身局部包围盒的最大边 × 世界缩放
        dims = obj_world_size(o)
        if max(dims) < min_size:
            victims.append(o)
    for o in victims:
        bpy.data.objects.remove(o, do_unlink=True)
    print("[archviz] 删掉 %d 个极小物件（< %.3f m）" % (len(victims), min_size))
    return len(victims)


def obj_world_size(o):
    if not o.data.vertices:
        return Vector((0, 0, 0))
    xs = [v.co.x for v in o.data.vertices]
    ys = [v.co.y for v in o.data.vertices]
    zs = [v.co.z for v in o.data.vertices]
    s = o.matrix_world.to_scale()
    return Vector((max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))) * Vector(
        (abs(s.x), abs(s.y), abs(s.z)))


def is_joinable(o, keep_animated):
    if not keep_animated:
        return True
    if o.animation_data is not None and o.animation_data.action is not None:
        return False
    if o.data.shape_keys is not None:
        return False
    if o.parent is not None and o.parent.type in ("ARMATURE", "EMPTY"):
        return False
    return True


def merge_by(mode, keep_animated):
    """把网格合并。返回 (合并前物件数, 合并后物件数)。"""
    objs = [o for o in mesh_objects() if is_joinable(o, keep_animated)]
    if len(objs) < 2 or mode == "none":
        return len(objs), len(objs)

    before = len(objs)

    if mode == "all":
        groups = [objs]
    else:
        # 按「材质名组合」分组：材质完全相同的才合，合并后表面数不变、draw call 变少
        buckets = {}
        for o in objs:
            key = tuple(sorted(
                (s.material.name if s.material else "__none__")
                for s in o.material_slots)) or ("__empty__",)
            buckets.setdefault(key, []).append(o)
        groups = [g for g in buckets.values() if len(g) > 1]

    merged = 0
    for group in groups:
        if len(group) < 2:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in group:
            o.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        try:
            bpy.ops.object.join()
            merged += 1
        except RuntimeError as e:
            print("[archviz]   合并失败（跳过这组 %d 个）：%s" % (len(group), e))

    after = len(mesh_objects())
    print("[archviz] 按%s合并：%d 个物件 → %d 个（合了 %d 组）"
          % ("材质" if mode == "material" else "全部", before, after, merged))
    return before, after


def apply_decimate(ratio):
    if ratio <= 0.0 or ratio >= 1.0:
        return
    total_before = 0
    total_after = 0
    for o in mesh_objects():
        before = tri_count(o)
        if before < 200:      # 太小的别减，减了只会变形
            continue
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        m = o.modifiers.new(name="decimate", type="DECIMATE")
        m.ratio = ratio
        m.use_collapse_triangulate = True
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except RuntimeError as e:
            print("[archviz]   减面失败 %s：%s" % (o.name, e))
            o.modifiers.remove(m)
            continue
        total_before += before
        total_after += tri_count(o)
    print("[archviz] 减面 ratio=%.2f：%d → %d 三角（省 %.0f%%）" % (
        ratio, total_before, total_after,
        100.0 * (1.0 - total_after / max(total_before, 1))))


# 自适应减面：按物件**自己的**三角数决定减多狠。
#
# 为什么需要（爱给网那套电竞酒店实测，2026-11-06）：
#   8,888,803 三角里，**21 个物件占了 42.1%**（374 万），而 630 个 <1000 面的小件
#   加起来才 6.2%。最重的几个是：
#       Circle019 / Circle021     各 478,834 三角   ← 圆形地毯
#       JS2973/3034/3095/3156     各 142,648 三角   ← 四把同款
#       odeyalo048/049            各 123,300 三角   ← 毯子（俄文 одеяло）
#   地毯/毛毯做到 47 万面，是扫描/布料模拟直接倒出来的，玩家俯视根本看不出差别。
#   而对**墙、地板、大台面**乱减面会露馅（轮廓和接缝会崩）。
#
#   所以按档位来：越重的减越狠，轻的原样保留。
ADAPTIVE_TIERS = [
    (200000, 0.06),   # ≥20 万面：装饰性大件（地毯/毯子），砍到 6%
    (50000, 0.20),    # 5~20 万：砍到 20%
    (20000, 0.40),    # 2~5 万：砍到 40%
    (8000, 0.65),     # 0.8~2 万：砍到 65%
]
ADAPTIVE_FLOOR = 8000   # 低于这个面数的物件**一点不动**


def apply_decimate_adaptive(extra_safety=1.0):
    """按 ADAPTIVE_TIERS 逐物件减面。`extra_safety` < 1 会整体更狠。"""
    total_before = 0
    total_after = 0
    touched = 0
    for o in mesh_objects():
        before = tri_count(o)
        if before <= ADAPTIVE_FLOOR:
            continue
        ratio = 1.0
        for threshold, r in ADAPTIVE_TIERS:
            if before >= threshold:
                ratio = r
                break
        ratio = max(0.02, min(1.0, ratio * extra_safety))
        if ratio >= 1.0:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        m = o.modifiers.new(name="decimate", type="DECIMATE")
        m.ratio = ratio
        m.use_collapse_triangulate = True
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except RuntimeError as e:
            print("[archviz]   减面失败 %s：%s" % (o.name, e))
            o.modifiers.remove(m)
            continue
        after = tri_count(o)
        total_before += before
        total_after += after
        touched += 1
        if before >= 100000:
            print("[archviz]   %-34s %9d → %9d（%.0f%%）"
                  % (o.name[:34], before, after, 100.0 * ratio))
    pct = 100.0 * (1.0 - total_after / max(total_before, 1))
    print("[archviz] 自适应减面：动了 %d 个物件，%d → %d 三角（省 %.0f%%）"
          % (touched, total_before, total_after, pct))


def shrink_textures(cap, low_cap=1024):
    """导出前把 Blender 里的贴图**真的缩小**（改像素，不只是改引用）。
    
    为什么要在这里做：GLB 把贴图**内嵌**，所以导出之后就没法在 Godot 里
    批量改了（`.import` 的 `_subresources` 键名很难手写对）。
    在 Blender 里缩完再导出，GLB 体积和进 Godot 之后的显存一起小。
    
    实测（爱给网那套）：32.4 M 像素 → 缩到 cap=1024 后约 12 M，显存 124 MB → 46 MB。
    """
    if cap <= 0:
        return
    imgs = [i for i in bpy.data.images if i.size[0] > 0 and i.source == "FILE"]
    before_px = 0
    after_px = 0
    touched = 0
    for img in imgs:
        w, h = img.size[0], img.size[1]
        before_px += w * h
        low = img.name.lower()
        c = low_cap if any(k in low for k in
                           ("bump", "normal", "rough", "metal", "ao", "mask", "spec", "gloss")) else cap
        if max(w, h) <= c:
            after_px += w * h
            continue
        s = c / float(max(w, h))
        nw = max(1, int(round(w * s)))
        nh = max(1, int(round(h * s)))
        try:
            img.scale(nw, nh)
            # 缩完必须真的落盘，否则导出时 GLB 里还是原图
            if img.packed_file is not None:
                img.pack()
            touched += 1
            after_px += nw * nh
            if w * h > 4_000_000:
                print("[archviz]   贴图 %-28s %dx%d → %dx%d"
                      % (img.name[:28], w, h, nw, nh))
        except Exception as e:  # noqa: BLE001
            print("[archviz]   缩图失败 %s：%s" % (img.name, e))
            after_px += w * h
    print("[archviz] 贴图缩到 %d 上限：动了 %d 张，%.1f M 像素 → %.1f M"
          % (cap, touched, before_px / 1e6, after_px / 1e6))
    print("[archviz]   RGBA8 显存 %.0f MB → %.0f MB（含 mip）"
          % (before_px * 4 * 1.333 / 1048576.0, after_px * 4 * 1.333 / 1048576.0))


def export_glb(path):
    d = os.path.dirname(os.path.abspath(path))
    if d:
        os.makedirs(d, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    kwargs = dict(
        filepath=path,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_materials="EXPORT",
    )
    # Blender 5.x 的参数名在不同小版本间抖过，缺参数就退回最小集合
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB")
    size = os.path.getsize(path)
    print("[archviz] 导出 %s（%.1f MB）" % (path, size / 1048576.0))


# ---------------------------------------------------------------- 主流程

def main():
    a = parse_args()
    if not os.path.exists(a.src):
        raise SystemExit("输入不存在：%s" % a.src)

    wipe_scene()
    print("[archviz] 导入 %s" % a.src)
    import_model(a.src)

    base = report("导入后")

    # ⚠️ 顺序很重要：**先减面、再合并**。
    #    合并之后每个物件变成一个「材质大杂烩」，就没法按单个物件的面数
    #    决定减多狠了（地毯该砍 94%、墙一点都不该动）。见 ADAPTIVE_TIERS 的说明。
    drop_tiny(a.min_size)
    if a.decimate_adaptive:
        apply_decimate_adaptive(a.decimate_safety)
    elif a.decimate > 0.0:
        apply_decimate(a.decimate)

    merge_mode = "none" if a.no_merge else a.merge
    merge_by(merge_mode, a.keep_animated)

    if a.texture_cap > 0:
        shrink_textures(a.texture_cap)

    final = report("优化后")

    if base["surfaces"] > 0:
        print("[archviz] 表面数 %d → %d（%.1f%%）"
              % (base["surfaces"], final["surfaces"],
                 100.0 * final["surfaces"] / base["surfaces"]))
    if base["tris"] > 0:
        print("[archviz] 三角数 %d → %d（%.1f%%）"
              % (base["tris"], final["tris"],
                 100.0 * final["tris"] / base["tris"]))

    if a.report or not a.dst:
        print("[archviz] --report：没有导出")
        return
    export_glb(a.dst)


if __name__ == "__main__":
    main()

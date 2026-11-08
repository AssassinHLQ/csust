# -*- coding: utf-8 -*-
"""把「游戏开发电竞房」的 Rhino FBX 清理成 Godot 能用的 GLB。

用法（Blender 5.2）：
    D:/SOFTWARE/Blender52/blender.exe --background --factory-startup \
        --python tools/build_esports_room.py -- "C:/Users/William/Desktop/游戏开发电竞房.fbx"

输入是使用者从爱给网那套「现代网咖/电竞酒店套房」改版后、在 Rhino 里导出的 FBX。
实测（`tools/inspect_esports_fbx.py`）有五个坑：

  1. **7.59M 三角面 / 780 对象 / 60 材质**：直接导进 Godot 会卡死。
  2. **整屋疑似重复**：218 个对象的包围盒和另一份几乎重合（中心差 ≤ 3 cm）。
     这里按「AABB 同尺寸 + 中心差 ≤ 2 cm + 面数相同」挑掉多余的一份。
  3. **Rhino 贴图路径是绝对路径**（`C:/Users/.../UnpackedFiles/...`），
     拷到别的机器就变成纯色；导出前把能找到的贴图打包进 GLB。
  4. **坐标轴没转**：Rhino 是 Z-up，Godot 是 Y-up，直接开会躺倒。
  5. **原点不在房间底面中心**：摆位要对半天。

输出：`models/esports_room/esports_room.glb`
  · Y-up、地板面 y = 0、水平中心 (0, 0)；
  · 面数按 `--target-tris`（默认 45 万）自适应抽稀，大件不动、小件猛减；
  · 材质按材质合并（每材质 1 个网格 = 1 次 draw call），贴图内嵌、最大边 1024。

⚠️ 按材质合并之后**不能再单独移动/隐藏**某一间家具 —— 静态房子没影响。
"""
import argparse
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_SRC = r"C:\Users\WY157\Desktop\游戏开发电竞房.fbx"
DEFAULT_DST = os.path.join(ROOT, "models", "esports_room", "esports_room.glb")


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    # 也接受「不写 --in，直接甩一个路径」：blender -b -P script.py -- 某某.fbx
    if argv and not argv[0].startswith("-") and os.path.splitext(argv[0])[1].lower() in (
            ".fbx", ".obj", ".glb", ".gltf"):
        argv = ["--in", argv[0]] + argv[1:]
    ap = argparse.ArgumentParser(prog="build_esports_room")
    ap.add_argument("--in", dest="src", default=DEFAULT_SRC)
    ap.add_argument("--out", dest="dst", default=DEFAULT_DST)
    ap.add_argument("--target-tris", type=int, default=450_000,
                    help="导出后的三角面上限（默认 45 万）")
    ap.add_argument("--tex", type=int, default=1024, help="贴图最大边（0=不动）")
    ap.add_argument("--dedupe-eps", type=float, default=0.02, help="判重中心差（米）")
    ap.add_argument("--keep-parts", action="store_true",
                    help="不按材质合并（调试用：能单独看每一件家具）")
    return ap.parse_args(argv)


def tri_count(obj):
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def world_aabb(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    return lo, hi


def log(*a):
    print("[esports]", *a, flush=True)


# ---------------------------------------------------------------- ① 载入

def load(src):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    log("载入 %s（%.1f MB）" % (src, os.path.getsize(src) / 1e6))
    bpy.ops.import_scene.fbx(filepath=src, use_custom_normals=True)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    log("对象 %d / 三角面 %d" % (len(meshes), sum(tri_count(o) for o in meshes)))
    return meshes


# ---------------------------------------------------------------- ② 去重

def dedupe(meshes, eps):
    """同尺寸 + 同面数 + 中心很近 = 重复，留名字短的那份（通常是不带 `_2` 的原始件）。"""
    info = []
    for o in meshes:
        lo, hi = world_aabb(o)
        info.append((o, lo, hi, hi - lo, tri_count(o)))
    drop = set()
    for i in range(len(info)):
        o1, a1, b1, s1, t1 = info[i]
        if o1.name in drop:
            continue
        for j in range(i + 1, len(info)):
            o2, a2, b2, s2, t2 = info[j]
            if o2.name in drop or t1 != t2:
                continue
            if (s1 - s2).length > 0.01:
                continue
            if ((a1 + b1) * 0.5 - (a2 + b2) * 0.5).length > eps:
                continue
            # 留短名
            loser = o2 if len(o2.name) < len(o1.name) else o1
            winner = o1 if loser is o2 else o2
            drop.add(loser.name)
            if loser is o1:
                break
    removed = 0
    for name in drop:
        o = bpy.data.objects.get(name)
        if o is not None:
            removed += tri_count(o)
            bpy.data.objects.remove(o, do_unlink=True)
    log("去重：删 %d 个对象 / %d 三角面" % (len(drop), removed))


# ---------------------------------------------------------------- ③ 坐标轴

def aabb_size(meshes):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        a, b = world_aabb(o)
        for i in range(3):
            lo[i] = min(lo[i], a[i])
            hi[i] = max(hi[i], b[i])
    return hi - lo


def fix_axes(meshes):
    """把房间摆正：**高度落在 Blender 的 Z 上**，长边落在 Y 上。

    ⚠️ 第一版这里是「绕 X 转 -90° 把 Z-up 掰成 Y-up」，结果 Godot 里量出来
      尺寸是 (10.40, **16.84**, 3.60) —— 房子立起来了，高度变成 16.84 m。
      原因：Blender 的 FBX 导入器本身已经做过「Y-up → Z-up」，
      `matrix_world` 里就带着那一次旋转，再手动转一次就是多转。
      现在改成**量完再转**：高 ≈ 3.6 才算对，不对就绕 X 转 +90° 把高度挪回 Z。
      真正换成 Godot 的 Y-up 是导出时 `export_yup=True` 的事，这里不管。
    """
    size = aabb_size(meshes)
    log("导入后包围盒 size=(%.3f, %.3f, %.3f)" % (size.x, size.y, size.z))
    if size.y > size.z:
        log("长边在 Y、矮边在 Z（房子躺/立反了）→ 绕 X 转 +90°，把高度挪回 Z")
        rot = Matrix.Rotation(1.5707963267948966, 4, "X")
        for o in meshes:
            o.data.transform(rot @ o.matrix_world)
            o.matrix_world = Matrix.Identity(4)
        bpy.context.view_layer.update()
        size = aabb_size(meshes)
        log("转完 size=(%.3f, %.3f, %.3f)" % (size.x, size.y, size.z))
    return center_and_floor(meshes)


def center_and_floor(meshes):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        a, b = world_aabb(o)
        for i in range(3):
            lo[i] = min(lo[i], a[i])
            hi[i] = max(hi[i], b[i])
    shift = Vector((-(lo.x + hi.x) * 0.5, -lo.y, -(lo.z + hi.z) * 0.5))
    for o in meshes:
        o.data.transform(Matrix.Translation(shift) @ o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    bpy.context.view_layer.update()
    return shift


# ---------------------------------------------------------------- ④ 贴图打包

def pack_textures(cap):
    """Rhino 导出 10 MB 的贴图就够用，多半是 4K JPEG。
    ⚠️ 必须在**减面之前**打包：减面会把对象换成新网格，材质槽连带贴图会丢
      （第一版就是这个顺序：日志「打包 0 张」、最后 GLB 28.9 MB = 只剩几何）。"""
    n_ok = 0
    n_missing = 0
    for img in bpy.data.images:
        if img.source != "FILE":
            continue
        p = bpy.path.abspath(img.filepath) if img.filepath else ""
        if not p or not os.path.exists(p):
            n_missing += 1
            log("  缺贴图 %s" % (img.filepath or img.name))
            continue
        img.reload()
        if cap and max(img.size[0], img.size[1]) > cap:
            scale = cap / float(max(img.size[0], img.size[1]))
            img.scale(int(img.size[0] * scale), int(img.size[1] * scale))
        if img.packed_file is None:
            img.pack()
        n_ok += 1
    log("贴图打包 %d 张，缺 %d 张" % (n_ok, n_missing))


# ---------------------------------------------------------------- ⑤ 减面

## 窗帘这类「一片薄布」的判据：某一维 < 8 cm，另一维 > 1.5 m，面数够多。
## 这种网格**一律不减面** —— COLLAPSE 会把褶皱的顶点合并掉，法线跟着碎成一片。
##
## ⚠️ 阈值为什么是 8 cm 而不是 25 cm（2026-11-08 实测）：
##    25 cm 会把「柜子背板 / 桌腿薄板」也算成窗帘，一口气保护了 10 个网格，
##    面数从 105 万飙到 236 万、文件 47 MB → 88 MB，性能代价太大。
##    真正怕减的是**只有几厘米厚的布料**（实测窗帘是 0.02~0.05 m）。
def is_sheet(o):
    s = o.dimensions
    dims = sorted([s.x, s.y, s.z])
    return dims[0] < 0.08 and dims[2] > 1.5 and tri_count(o) >= 500


def decimate(meshes, target):
    total = sum(tri_count(o) for o in meshes)
    if total <= target:
        log("减面：%d ≤ %d，跳过" % (total, target))
        return
    ratio = target / float(total)
    log("减面：%d → 目标 %d（整体 ×%.3f）" % (total, target, ratio))
    big = sorted(meshes, key=lambda o: -tri_count(o))
    log("面数最大的 5 件：%s" % ", ".join(
        "%s=%d" % (o.name, tri_count(o)) for o in big[:5]))
    # 大件（≥2 万面）单独算：它们占大头，按整体比例减才减得动；
    # 小件给个下限，别把椅子减成色块。
    heavy = sum(tri_count(o) for o in meshes if tri_count(o) >= 20000)
    if heavy > 0 and heavy > target * 0.5:
        h_ratio = min(1.0, (target * 0.85) / float(heavy))
    else:
        h_ratio = ratio
    log("大件（≥2 万面，合计 %d）单独 ×%.3f，其余 ×%.3f" % (heavy, h_ratio, ratio))
    skipped_sheets = 0
    for o in meshes:
        t = tri_count(o)
        if t < 400:
            continue  # 太小的别减，减了只会变形
        # ⚠️ 薄片（窗帘 / 纱帘 / 幕布）不减：COLLAPSE 会把相邻褶皱的顶点并掉，
        #    自定义法线跟着错位，Godot 里就是一地碎条（2026-11-08 实测：
        #    M_集简空间h06_m21090330 面料内法线夹角 >30° 占 34.2%）。
        if is_sheet(o):
            skipped_sheets += 1
            continue
        r = h_ratio if t >= 20000 else max(ratio, 0.35)
        if r >= 0.999:
            continue
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        m = o.modifiers.new("dec", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = max(0.02, r)
        m.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=m.name)
        o.select_set(False)
    after = sum(tri_count(o) for o in bpy.context.scene.objects if o.type == "MESH")
    log("减面后 %d 三角面（跳过 %d 片窗帘/薄布）" % (after, skipped_sheets))


# ---------------------------------------------------------------- ⑤b 重算法线
#
# ⚠️ 2026-11-08 必做，否则 Godot 里窗帘碎成一条条：
#   `import_scene.fbx(use_custom_normals=True)` 把法线**钉死**在原始顶点上；
#   DECIMATE(COLLAPSE) 重排三角面之后，这些钉子就和几何对不上了 ——
#   实测 M_集简空间h06_m21090330 面内顶点法线夹角 >30° 的占 34.2%、
#   邻面夹角 >30° 的占 32.4%（原始 FBX 是 0.1% / 0.0%）。
#   所以减面之后必须**重算法线**：先清掉自定义法线，再按角度平滑。
def recalc_normals(meshes, angle_deg=40.0):
    import math as _math
    bpy.ops.object.select_all(action="DESELECT")
    n_done = 0
    for o in meshes:
        if o.type != "MESH" or tri_count(o) == 0:
            continue
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        # 清掉 FBX 带进来的自定义法线，让 Blender 自己算
        try:
            o.data.free_normals_split()
        except AttributeError:
            pass  # 4.x 已经没有这个 API，custom normals 随 attribute 一起清
        try:
            o.data.normals_split_custom_set([])
        except (AttributeError, RuntimeError):
            pass
        # 进入编辑模式，全选，按角度平滑（保持硬边）
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        try:
            bpy.ops.mesh.normals_make_consistent(inside=False)  # 朝外
        except RuntimeError as e:
            log("  normals_make_consistent 失败 %s: %s" % (o.name, e))
        bpy.ops.object.mode_set(mode="OBJECT")
        # 用自动平滑修改器（4.1+ 的 shade_smooth_by_angle 等价物）
        try:
            bpy.ops.object.shade_smooth_by_angle(angle=_math.radians(angle_deg))
        except (AttributeError, RuntimeError, TypeError):
            try:
                bpy.ops.object.shade_smooth()
            except RuntimeError:
                pass
        o.select_set(False)
        n_done += 1
    log("法线重算：%d 个网格（平滑角 %.0f°）" % (n_done, angle_deg))


# ---------------------------------------------------------------- ⑥ 按材质合并

def merge_by_material(meshes):
    """每个材质 join 成一个对象。合并前先把多材质槽的对象按材质拆开，
    否则 join 之后一个对象里还是一堆槽，draw call 省不下来。"""
    bpy.ops.object.select_all(action="DESELECT")
    # 先按材质拆多槽件
    for o in list(meshes):
        if len([s for s in o.material_slots if s.material]) > 1:
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            try:
                bpy.ops.mesh.separate(type="MATERIAL")
            except RuntimeError:
                pass
    bpy.ops.object.select_all(action="DESELECT")
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]

    buckets = {}
    for o in meshes:
        m = o.material_slots[0].material if o.material_slots else None
        key = m.name if m else "<none>"
        buckets.setdefault(key, []).append(o)
    log("按材质合并：%d 个对象 → %d 个材质桶" % (len(meshes), len(buckets)))
    out = []
    for key, group in buckets.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in group:
            o.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        if len(group) > 1:
            bpy.ops.object.join()
        joined = bpy.context.view_layer.objects.active
        joined.name = "M_" + key[:40]
        joined.select_set(False)
        out.append(joined)
    return out


# ---------------------------------------------------------------- ⑦ 导出

def export(dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=dst,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=False,  # ⚠️ 这里**关掉**轴转换：Rhino→FBX→Blender 那一路已经把地址摆正，
                           #    再让导出器转一次，Godot 里就变成「房子侧躺」（高 3.6 落到 Z 上）。
                           #    关掉之后 Blender 的坐标原样写进 glTF，Godot 端起就是 Y-up。
        export_draco_mesh_compression_enable=False,  # Godot 4 不认 Draco
        export_image_format="AUTO",
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )
    log("写出 %s（%.1f MB）" % (dst, os.path.getsize(dst) / 1e6))


def main():
    a = parse_args()
    meshes = load(a.src)
    dedupe(meshes, a.dedupe_eps)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    fix_axes(meshes)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    pack_textures(a.tex)
    decimate(meshes, a.target_tris)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    # ⚠️ 减面之后必须重算法线（自定义法线已被 COLLAPSE 打乱，见 recalc_normals 注释）
    recalc_normals(meshes)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not a.keep_parts:
        meshes = merge_by_material(meshes)
    else:
        log("--keep-parts：保持 %d 个对象不合并" % len(meshes))
    export(a.dst)

    # 收尾体检
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        a1, b1 = world_aabb(o)
        for i in range(3):
            lo[i] = min(lo[i], a1[i])
            hi[i] = max(hi[i], b1[i])
    log("最终：%d 对象 / %d 三角面 / 包围盒 min=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f)" % (
        len(meshes), sum(tri_count(o) for o in meshes),
        lo.x, lo.y, lo.z, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z))


main()

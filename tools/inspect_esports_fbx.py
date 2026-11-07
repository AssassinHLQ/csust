"""体检：新「游戏开发电竞房」FBX —— 有没有整屋重复、坐标轴朝哪、包围盒多大、几个材质。

用法：
    D:/SOFTWARE/Blender52/blender.exe --background --factory-startup \
        --python tools/inspect_esports_fbx.py -- "C:/Users/William/Desktop/游戏开发电竞房.fbx"

只读：不写任何文件，只 print。给 `build_esports_room.py` 定参数用。
"""
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv
SRC = argv[argv.index("--") + 1] if "--" in argv and len(argv) > argv.index("--") + 1 else \
    r"C:\Users\WY157\Desktop\游戏开发电竞房.fbx"

# 清场：factory-startup 还留着一个 Cube
bpy.ops.wm.read_factory_settings(use_empty=True)

print("[fbx] 载入 %s（%.1f MB）" % (SRC, os.path.getsize(SRC) / 1e6))
bpy.ops.import_scene.fbx(filepath=SRC, use_custom_normals=True)

objs = [o for o in bpy.context.scene.objects]
meshes = [o for o in objs if o.type == "MESH"]
empties = [o for o in objs if o.type == "EMPTY"]
print("[fbx] 对象 %d（网格 %d / 空 %d / 其它 %d）" % (
    len(objs), len(meshes), len(empties), len(objs) - len(meshes) - len(empties)))

tris = 0
for o in meshes:
    me = o.data
    me.calc_loop_triangles()
    tris += len(me.loop_triangles)
print("[fbx] 三角面合计 %d" % tris)


def world_aabb(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    return lo, hi


lo = Vector((1e9, 1e9, 1e9))
hi = Vector((-1e9, -1e9, -1e9))
for o in meshes:
    a, b = world_aabb(o)
    for i in range(3):
        lo[i] = min(lo[i], a[i])
        hi[i] = max(hi[i], b[i])
print("[fbx] 总包围盒 min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f) size=(%.3f, %.3f, %.3f)" % (
    lo.x, lo.y, lo.z, hi.x, hi.y, hi.z, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z))

# 重复检测：AABB 同尺寸 + 中心很近
print("[fbx] ── 疑似整屋重复（AABB 同尺寸 + 中心差 ≤ 0.12）──")
box = []
for o in meshes:
    a, b = world_aabb(o)
    box.append((o.name, a, b))
pairs = 0
seen = set()
for i in range(len(box)):
    for j in range(i + 1, len(box)):
        n1, a1, b1 = box[i]
        n2, a2, b2 = box[j]
        s1 = b1 - a1
        s2 = b2 - a2
        if (s1 - s2).length > 0.01:
            continue
        c1 = (a1 + b1) * 0.5
        c2 = (a2 + b2) * 0.5
        d = (c1 - c2).length
        if d <= 0.12:
            pairs += 1
            if pairs <= 8:
                print("   %s ≈ %s  （中心差 %.3f m）" % (n1, n2, d))
            seen.add(n1)
            seen.add(n2)
print("[fbx] 疑似重复对象 %d 个" % len(seen))

# 材质
mats = {}
for o in meshes:
    for slot in o.material_slots:
        m = slot.material
        if m is None:
            mats["<无材质>"] = mats.get("<无材质>", 0) + 1
            continue
        mats[m.name] = mats.get(m.name, 0) + 1
print("[fbx] 材质 %d 种（按面槽计次）：" % len(mats))
for k, v in sorted(mats.items(), key=lambda kv: -kv[1])[:40]:
    print("   %-44s ×%d" % (k, v))

# 贴图
imgs = [i for i in bpy.data.images if i.source == "FILE"]
print("[fbx] 外部贴图 %d 张" % len(imgs))
for i in imgs[:10]:
    print("   %s" % (i.filepath or i.name))

# 最大的 10 个对象（判断是不是「一面墙一个大盒子」）
sizes = []
for o in meshes:
    a, b = world_aabb(o)
    sizes.append(((b - a).length, o.name, len(o.data.polygons)))
sizes.sort(reverse=True)
print("[fbx] 最大的 10 个对象（对角长 / 名字 / 面数）：")
for d, n, p in sizes[:10]:
    print("   %.2f m  %-40s %d 面" % (d, n, p))
print("[fbx] 最小的 5 个对象：")
for d, n, p in sizes[-5:]:
    print("   %.3f m  %-40s %d 面" % (d, n, p))

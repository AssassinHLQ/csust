"""把「游戏开发部部室」的 Rhino GLB 清理成 Godot 能用的版本。

用法（Blender 5.2）：
    D:/SOFTWARE/Blender52/blender.exe --background --factory-startup \
        --python tools/build_gamedev_room.py -- "C:/Users/WY157/Desktop/游戏开发部.glb"

输入是用户从 Sketchfab 下载、再在 Rhino 里围了四面墙 + 天花板的导出件，有四个坑：

  1. **整屋复制了一份**：每个网格都有一个中心差 5.3 cm 的副本，直接导进 Godot
     会看见双份家具、面数翻倍；按「AABB 同尺寸 + 中心差 ≤ 12 cm」成对删掉。
  2. **Draco 压缩**：Godot 4 的 glTF 导入器不认 KHR_draco_mesh_compression，
     必须解压重导（Blender 导 GLB 时关掉 Draco）。
  3. **坐标轴没转**：Rhino 的 Z-up 数据直接写进 glTF，模型在 Blender/Godot 里
     是躺倒的；这里先转 Blender Z-up，再绕 Z 转 180° 让门朝 -Z（Godot 北）。
  4. **原点不在房间**：把包围盒中心放到 x/z = 0，地板面放到 y = 0，
     摆放时只需要给一个位置，不用再算偏移。

输出：`models/gamedev_room/gamedev_room.glb`（合并成 1 个网格、31 个材质面、
约 2.19 万三角面、贴图内嵌，不带 Draco）。
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DST = os.path.join(ROOT, "models", "gamedev_room", "gamedev_room.glb")
DEFAULT_SRC = r"C:\Users\WY157\Desktop\游戏开发部.glb"

argv = sys.argv
SRC = argv[argv.index("--") + 1] if "--" in argv and len(argv) > argv.index("--") + 1 else DEFAULT_SRC


def world_aabb(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(v.x for v in corners), min(v.y for v in corners), min(v.z for v in corners)))
    hi = Vector((max(v.x for v in corners), max(v.y for v in corners), max(v.z for v in corners)))
    return lo, hi


def suffix_rank(name):
    tail = name.rsplit(".", 1)
    if len(tail) == 2 and tail[1].isdigit():
        return int(tail[1])
    return 0


def main():
    if not os.path.isfile(SRC):
        raise SystemExit("找不到输入文件：%s" % SRC)
    os.makedirs(os.path.dirname(DST), exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    print("IMPORTED", len(meshes))

    # ── 1. 去重：成对的网格只留名字最“干净”的那份 ──
    info = [(o, *world_aabb(o)) for o in meshes]
    removed = set()
    keep = []
    for i, (o1, lo1, hi1) in enumerate(info):
        if o1 in removed:
            continue
        s1 = hi1 - lo1
        c1 = (lo1 + hi1) * 0.5
        group = [o1]
        for o2, lo2, hi2 in info[i + 1:]:
            if o2 in removed or o2 in group:
                continue
            if (s1 - (hi2 - lo2)).length < 0.02 and (c1 - (lo2 + hi2) * 0.5).length < 0.12:
                group.append(o2)
        if len(group) > 1:
            group.sort(key=lambda o: (suffix_rank(o.name), o.name))
            keep.append(group[0])
            removed.update(group[1:])
        else:
            keep.append(o1)
    for o in removed:
        bpy.data.objects.remove(o, do_unlink=True)
    print("DEDUPED_OBJECTS", len(removed), "LEFT", len(keep))

    # ── 2. 摆正（Z-up）+ 转 180°（门朝 -Z）──
    rot = Matrix.Rotation(math.radians(180), 4, "Z") @ Matrix.Rotation(math.radians(-90), 4, "X")
    for o in keep:
        o.matrix_world = rot @ o.matrix_world
    bpy.context.view_layer.update()

    # 地板顶面：GROUND / tile 是最底下那层，取它的最高点（摆正后 +Z 是上）
    floor_top = max(
        world_aabb(o)[1].z for o in keep
        if o.name.startswith("GROUND") or "tile_2x2" in o.name
    )
    print("FLOOR_TOP", round(floor_top, 3))

    # ── 3. 合并成一个网格 ──
    bpy.ops.object.select_all(action="DESELECT")
    for o in keep:
        o.select_set(True)
    bpy.context.view_layer.objects.active = keep[0]
    bpy.ops.object.join()
    room = bpy.context.view_layer.objects.active
    room.name = "GameDevRoom"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # ── 4. 原点：x/z 居中、地板面 y = 0 ──
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for v in room.data.vertices:
        w = room.matrix_world @ v.co
        for k in range(3):
            lo[k] = min(lo[k], w[k])
            hi[k] = max(hi[k], w[k])
    offset = Vector(((lo.x + hi.x) * -0.5, (lo.y + hi.y) * -0.5, -floor_top))
    for v in room.data.vertices:
        v.co += offset

    lo2 = Vector((1e9, 1e9, 1e9))
    hi2 = Vector((-1e9, -1e9, -1e9))
    for v in room.data.vertices:
        w = room.matrix_world @ v.co
        for k in range(3):
            lo2[k] = min(lo2[k], w[k])
            hi2[k] = max(hi2[k], w[k])
    room.data.calc_loop_triangles()
    print("FINAL_BOUNDS", tuple(round(v, 3) for v in lo2), tuple(round(v, 3) for v in hi2))
    print("FINAL_SIZE", tuple(round(v, 3) for v in (hi2 - lo2)))
    print("TRIS", len(room.data.loop_triangles), "VERTS", len(room.data.vertices),
          "MATERIALS", len(room.data.materials))

    # ── 5. 导出（Godot 不认 Draco，务必关掉）──
    bpy.ops.object.select_all(action="DESELECT")
    room.select_set(True)
    bpy.context.view_layer.objects.active = room
    bpy.ops.export_scene.gltf(
        filepath=DST,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_draco_mesh_compression_enable=False,
        export_animations=False,
        export_lights=False,
        export_cameras=False,
    )
    print("EXPORTED", DST)


main()

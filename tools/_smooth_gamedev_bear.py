"""把「游戏开发部部室」GLB 里的粉熊改成平滑着色（不改几何、不加面）。

    blender -b --python tools/_smooth_gamedev_bear.py

背景（2026-11-04 用户问「粉色熊有没有渲染圆角，网格的渲染圆角」）：
那份 GLB 里熊是**硬边平面着色** —— 实测 teddybear 那 1,026 个面：
顶点 1,446 / 唯一点位 570（重复 2.54×，每个硬边都拆了顶点），
顶点法线与面法线夹角中位仅 2.1°（几乎完全贴平面）。所以看着一块块大棱面。

这份脚本只做一件事：给材质名含 `teddybear` 的那些面做 shade smooth。
· 面数不变（实测 21,892 → 21,892），不加几何
· 只影响着色法线，轮廓仍是低模多边形（要真圆角得倒角/细分，那会加面数）

⚠️ 选面必须按 `polygon.material_index` 精确挑。用 `material_slot_select()`
   会在导入后的合并网格上把**全部 21,892 个面**选中（本喵踩过，直接倒角到整间屋子）。
⚠️ 平滑要用编辑模式下的 `mesh.faces_shade_smooth()`；
   `object.shade_smooth()` 是作用于整个对象/物体的。

模型本体 `models/gamedev_room/` 被 .gitignore 挡住（Sketchfab 素材、授权未核实），
所以**这个脚本就是那次改动的唯一记录**；换机器重跑一遍即可复现。
"""

import bpy
import sys
from collections import Counter

SRC = "res://models/gamedev_room/gamedev_room.glb"
KEY = "teddybear"

# 允许从命令行覆盖路径：blender -b --python 本脚本 -- <src> <dst>
argv = sys.argv
args = argv[argv.index("--") + 1:] if "--" in argv else []
SRC = args[0] if len(args) > 0 else SRC
OUT = args[1] if len(args) > 1 else SRC

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

obj = next((o for o in bpy.data.objects if o.type == 'MESH'), None)
if obj is None:
    print("[bear] 没有网格")
    sys.exit(1)
me = obj.data
cnt = Counter(p.material_index for p in me.polygons)
print("[bear] %s：顶点 %d 面 %d 材质槽 %d" % (
    obj.name, len(me.vertices), len(me.polygons), len(me.materials)))

want = [i for i, m in enumerate(me.materials) if m and KEY in m.name.lower()]
if not want:
    print("[bear] 没找到材质名含 %r 的槽" % KEY)
    sys.exit(2)
for i in want:
    print("[bear] 目标槽 %d：%s（%d 面）" % (i, me.materials[i].name, cnt.get(i, 0)))

bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
# 按 material_index 精确选面（见文件头 ⚠️）
for p in me.polygons:
    p.select = p.material_index in want
print("[bear] 精确选中 %d 面" % sum(1 for p in me.polygons if p.select))

bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.faces_shade_smooth()
bpy.ops.object.mode_set(mode='OBJECT')

tris = 0
for o in bpy.data.objects:
    if o.type == 'MESH':
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
print("[bear] 平滑完成，总三角 %d（应与原来相同）" % tris)

bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=False)
print("[bear] 导出 %s" % OUT)

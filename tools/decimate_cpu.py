"""用 Blender 把 9950X3D 减面成一个低模 GLB（默认目标 ~3,000 面）。

    blender -b --factory-startup --python tools/decimate_cpu.py -- <源.glb> <目标.glb> [面数]

源模型 12,386 面、摆 149 颗，是这个工程里最大的单件图元来源。
自动 LOD 实测无效（lod_bias 1→64 图元不动），所以做一个**显式的低模**，
运行时按距离用 `visibility_range` 切换。
"""
import sys

import bpy

SRC = r"C:\Users\WY157\Desktop\GODOT\_arisu_learn\models\cpu_9950x3d\ryzen_9950x3d.glb"
DST = r"C:\Users\WY157\Desktop\GODOT\_arisu_learn\models\cpu_9950x3d\ryzen_9950x3d_lod.glb"
TARGET_TRIS = 3000


def _args():
    rest = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    src = rest[0] if len(rest) > 0 else SRC
    dst = rest[1] if len(rest) > 1 else DST
    n = int(rest[2]) if len(rest) > 2 else TARGET_TRIS
    return src, dst, n


def count_tris() -> int:
    total = 0
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH":
            continue
        me = ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
        total += sum(len(p.vertices) - 2 for p in me.polygons)
        ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
    return total


def main():
    src, dst, target = _args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)

    before = count_tris()
    ratio = max(0.01, min(1.0, float(target) / float(max(before, 1))))
    print(f"[decimate] 减面前 {before} 面，目标 {target} → ratio {ratio:.3f}")

    for ob in list(bpy.context.scene.objects):
        if ob.type != "MESH":
            continue
        mod = ob.modifiers.new(name="Decimate", type="DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        mod.use_collapse_triangulate = True

    after = count_tris()
    print(f"[decimate] 减面后 {after} 面")

    bpy.ops.export_scene.gltf(
        filepath=dst,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
    )
    print(f"[decimate] 已导出 {dst}")


main()

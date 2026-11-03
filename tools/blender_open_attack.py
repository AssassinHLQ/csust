"""在 Blender 里打开 Arisu 的一条动作，直接把时间线定到它的帧范围。

用法（命令行）：
    blender --python tools/blender_open_attack.py -- <glb路径> <动作名> [帧率]

例：
    blender --python tools/blender_open_attack.py -- ^
        models/Arisu_ext.glb Normal_Attack_Ing 24

不传参数时的默认值就在下面。重点：**glTF 只存秒，帧数取决于帧率**，
所以脚本会把场景帧率设成你给的那个，再报「Blender 看到的帧范围」。
"""
import os
import sys

import bpy

DEFAULT_GLB = r"C:\Users\WY157\Desktop\GODOT\_arisu_learn\models\Arisu_ext.glb"
DEFAULT_CLIP = "Normal_Attack_Ing"
DEFAULT_FPS = 24


def _args() -> tuple[str, str, int]:
    argv = sys.argv
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
    else:
        rest = []
    glb = rest[0] if len(rest) > 0 else DEFAULT_GLB
    clip = rest[1] if len(rest) > 1 else DEFAULT_CLIP
    try:
        fps = int(rest[2]) if len(rest) > 2 else DEFAULT_FPS
    except ValueError:
        fps = DEFAULT_FPS
    return glb, clip, fps


def main() -> None:
    glb, clip, fps = _args()

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = fps
    scene.render.fps_base = 1.0

    print("=" * 64)
    print(f"[open] 导入 {glb}")
    bpy.ops.import_scene.gltf(filepath=glb)

    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm is None:
        print("[open] !! 场景里没有骨架")
        print("=" * 64)
        return

    ad = arm.animation_data or arm.animation_data_create()
    act = bpy.data.actions.get(clip)
    if act is None:
        print(f"[open] !! 没有动作「{clip}」，现有：")
        for a in bpy.data.actions:
            print("        ", a.name)
        print("=" * 64)
        return

    ad.action = act
    # Blender 4.4+ 的 slotted action：挂上去之后还要挑一个 slot
    try:
        if hasattr(ad, "action_slot") and ad.action_slot is None and len(act.slots):
            ad.action_slot = act.slots[0]
    except Exception as exc:  # noqa: BLE001
        print(f"[open] slot 设置跳过：{exc}")

    rng = act.frame_range
    f0, f1 = int(round(rng[0])), int(round(rng[1]))
    scene.frame_start = f0
    scene.frame_end = f1
    scene.frame_set(f0)

    print(f"[open] 骨架      : {arm.name}")
    print(f"[open] 动作      : {act.name}")
    print(f"[open] 帧率      : {fps} fps")
    print(f"[open] 帧范围    : {f0} ~ {f1}")
    print(f"[open] 帧间隔数  : {f1 - f0}  （首尾都算就是 {f1 - f0 + 1} 个关键帧位置）")
    print(f"[open] 时长      : {(f1 - f0) / fps:.3f} s")
    print(f"[open] 总动作数  : {len(bpy.data.actions)}")
    print("=" * 64)


main()

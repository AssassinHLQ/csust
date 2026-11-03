"""把 Arisu 的一条动作烤成 .blend（已挂好骨架/动作/帧范围/帧率），再用 GUI 打开。

分两步是为了确定性：直接 `--python` 开 GUI 时，脚本跑完窗口里不一定停在
你要的那条动作上（视口、选中、活动对象都可能没跟上）。先把状态存进 .blend，
再用 blender <文件> 打开，屏幕上看到的就是存下来的那个状态。

    blender -b --factory-startup --python tools/blender_prep_attack.py -- <glb> <动作> <fps> <输出.blend>
"""
import os
import sys

import bpy

DEFAULT_GLB = r"C:\Users\WY157\Desktop\GODOT\_arisu_learn\models\Arisu_ext.glb"
DEFAULT_CLIP = "Normal_Attack_Ing"
DEFAULT_FPS = 24
DEFAULT_OUT = r"C:\Users\WY157\Desktop\GODOT\_arisu_learn\_log\arisu_attack.blend"


def _args() -> tuple[str, str, int, str]:
    rest = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    glb = rest[0] if len(rest) > 0 else DEFAULT_GLB
    clip = rest[1] if len(rest) > 1 else DEFAULT_CLIP
    try:
        fps = int(rest[2]) if len(rest) > 2 else DEFAULT_FPS
    except ValueError:
        fps = DEFAULT_FPS
    out = rest[3] if len(rest) > 3 else DEFAULT_OUT
    return glb, clip, fps, out


def main() -> None:
    glb, clip, fps, out = _args()

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = fps
    scene.render.fps_base = 1.0

    print(f"[prep] 导入 {glb}")
    bpy.ops.import_scene.gltf(filepath=glb)

    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm is None:
        print("[prep] !! 没有骨架，放弃")
        return

    act = bpy.data.actions.get(clip)
    if act is None:
        print(f"[prep] !! 没有动作 {clip}")
        return

    ad = arm.animation_data or arm.animation_data_create()
    ad.action = act
    try:
        if hasattr(ad, "action_slot") and ad.action_slot is None and len(act.slots):
            ad.action_slot = act.slots[0]
    except Exception as exc:  # noqa: BLE001
        print(f"[prep] slot 跳过：{exc}")

    rng = act.frame_range
    f0, f1 = int(round(rng[0])), int(round(rng[1]))
    scene.frame_start = f0
    scene.frame_end = f1
    scene.frame_set(f0)

    # 只选中骨架，打开时一眼能看到它
    for o in bpy.context.selected_objects:
        o.select_set(False)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm

    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out)

    print(f"[prep] 骨架 {arm.name} / 动作 {act.name} / {fps} fps / 帧 {f0}~{f1}"
          f"（{f1 - f0} 帧间隔）/ 时长 {(f1 - f0) / fps:.3f} s")
    print(f"[prep] 已保存 {out}")


main()

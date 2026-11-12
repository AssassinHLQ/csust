"""把「阿洛娜」的 Blender 源档转成游戏里用的 GLB。

用法（**后台跑，不弹窗口**）：
    D:\\SOFTWARE\\Blender52\\blender.exe --background --factory-startup \
        --python _tools/export_arona_glb.py

输出：`models/arona/arona.glb`（贴图已内嵌，约 1.3 MB）
     ⚠️ 这个 GLB 是**第三方素材的派生物**，`/models/arona/` 已被 .gitignore 排除，
        不随仓库分发。见 .gitignore 里那段说明与 CREDITS.md。

── 为什么需要这个脚本（三个坑，都是实测踩出来的）──
1. **源档里的贴图路径是坏的**：材质引用 `//Arona Body.png`（相对 `source/`、还是空格），
   而实际文件在 `../textures/Arona_Body.png`（下划线）。不改路径，导出就是纯白模型。
2. **路径里有中文**（`碧蓝档案 阿罗娜 3d模型_爱给网_aigei_com`），所以这里先把贴图
   复制到纯 ASCII 的临时目录再指过去，避免编码问题。
3. **材质是 MMD 的**（`mmd_shader` / `mmd_tex_uv` 节点组，来自 mmd_tools）：
   每个材质里有 **3 个 Material Output**，glTF 导出器会挑到接 `mmd_shader` 的那个、
   它看不懂 → 导出的材质只剩 `{name, doubleSided}`，没有 `pbrMetallicRoughness`、
   没有 `baseColorTexture`（`is_active_output` 改成 Principled 那条也没用，试过了）。
   所以这里**整块重建材质**：干净的 Principled BSDF + Image Texture。

验证导出是否带贴图（不用开 Godot，直接看 GLB 的 JSON）：
    GLB 结构 = 12 字节头 + 4 字节 JSON 长度 + JSON …
    在 JSON 里搜 `"images"` / `"baseColorTexture"`，各应出现 6 次。
"""

import os
import shutil
import sys

import bpy

# ── 路径（改这里就能换素材来源）──────────────────────────────────────────────
SRC_BLEND = (r"C:\Users\WY157\Downloads\爱给网下载"
             r"\碧蓝档案 阿罗娜 3d模型_爱给网_aigei_com\source"
             r"\[BlueArchive] - Arona.blend")
SRC_TEX_DIR = (r"C:\Users\WY157\Downloads\爱给网下载"
               r"\碧蓝档案 阿罗娜 3d模型_爱给网_aigei_com\textures")
# 贴图先搬到纯 ASCII 路径（坑 2）
ASCII_TEX_DIR = r"C:\Users\WY157\Desktop\GODOT\_log\arona_tex"
OUT_GLB = r"C:\Users\WY157\Desktop\GODOT\_arisu_learn\models\arona\arona.glb"

# 网格名（去掉 .001 之类后缀）→ 贴图文件。**顺序有意义**：Eyebrow 必须排在 Eye 前面，
# 否则 "Arona Eyebrow" 会被 startswith("Arona Eye") 抢走（第一版就配错了）。
MESH_TO_TEX = [
    ("Arona Eyebrow", "Arona_Eyebrow.png"),
    ("Arona Body", "Arona_Body.png"),
    ("Arona Eye", "Arona_Eye.png"),
    ("Arona Face", "Arona_Face.png"),
    ("Arona Hair", "Arona_Hair.png"),
    ("Arona Halo", "Arona_Halo.png"),
]


def stage_textures() -> None:
    """把贴图复制到 ASCII 目录（源文件名用 `_`，材质里引用的是空格版）。"""
    os.makedirs(ASCII_TEX_DIR, exist_ok=True)
    for _, fname in MESH_TO_TEX:
        src = os.path.join(SRC_TEX_DIR, fname)
        if not os.path.exists(src):
            sys.exit(f"[arona] 缺贴图: {src}")
        shutil.copyfile(src, os.path.join(ASCII_TEX_DIR, fname))
    print(f"[arona] 贴图已就位: {ASCII_TEX_DIR}")


def clean_material(name: str, tex_file: str) -> bpy.types.Material:
    """干净的 Principled + Image Texture（坑 3：不用 MMD 那套节点）。"""
    mat = bpy.data.materials.new("C_" + name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(
        os.path.join(ASCII_TEX_DIR, tex_file), check_existing=True)
    tex.interpolation = "Linear"

    out.location = (300, 0)
    bsdf.location = (0, 0)
    tex.location = (-320, 0)

    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    # 头发/刘海/眼睛的边缘靠 alpha 抠形，接上 Alpha 通道
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def main() -> None:
    stage_textures()
    bpy.ops.wm.open_mainfile(filepath=SRC_BLEND)

    # 顺带把源档里那些坏路径也修一下（不修的话 `pack_all()` 会整体失败，
    # 虽然本脚本不打包，但留着坏数据块容易误导后面的人）
    for im in bpy.data.images:
        if im.name in ("Render Result", "Viewer Node"):
            continue
        im.filepath = os.path.join(ASCII_TEX_DIR, im.name.replace(" ", "_"))

    assigned = 0
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        key = None
        for mesh_prefix, tex_file in MESH_TO_TEX:
            if obj.name.startswith(mesh_prefix):
                key = (mesh_prefix, tex_file)
                break
        if key is None:
            print(f"[arona] 跳过未知网格: {obj.name}")
            continue
        mat = clean_material(key[0], key[1])
        if not obj.material_slots:
            obj.data.materials.append(mat)
        else:
            for slot in obj.material_slots:
                slot.material = mat
        assigned += 1
        print(f"[arona] {obj.name} -> {key[1]}")

    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    # ⚠️ 不要 `pack_all()`：源档里的旧图像路径是坏的，打包会整体失败。
    #    导出器会直接从磁盘读图并内嵌进 GLB，不需要先打包。
    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB,
        export_format="GLB",
        use_selection=False,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    size = os.path.getsize(OUT_GLB)
    print(f"[arona] 导出完成: {OUT_GLB}  {size} 字节  材质 {assigned} 个")
    if size < 1_200_000:
        print("[arona] !! 文件偏小，很可能又没带上贴图 —— 检查上面有没有 '缺贴图'")


if __name__ == "__main__":
    main()

class_name GameDevRoom
extends Node3D
## 「游戏开发部部室」（商店东侧新地块）。
##
## 模型：`models/gamedev_room/gamedev_room.glb`，来自 Sketchfab 作者**起航扬帆了**的
## 《游戏开发部部室》，由用户先在 Rhino 里围了四面墙 + 天花板，再减面导出。
## 本地只做贴图/朝向/去重处理（见 tools/build_gamedev_room.py）——
## 授权不明，**不随仓库分发**，见 credits.gd 与 CREDITS.md。
##
## 为什么碰撞在运行时生成：
##   整个部室在 Blender 里合并成了一个 MeshInstance3D（31 个材质面），
##   `create_trimesh_collision()` 在 C++ 里一次性建好凹多边形，开局几毫秒，
##   比把 3 万多个顶点烘成 .tscn 里的文本形状干净得多。
##   门洞、窗户都在网格里，trimesh 天然就有洞，不用手摆碰撞盒。

@export var build_collision := true


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if build_collision:
		_build_collision()


func _build_collision() -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		push_warning("[GameDevRoom] 没有 Model 节点，碰撞不建")
		return
	var count := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		mi.create_trimesh_collision()
		count += 1
	print("[GameDevRoom] 碰撞：%d 个网格生成 trimesh" % count)

extends SceneTree
## 量：芹香为什么比玩家/同伴大一截。
##   _tools/run_probe.sh res://scripts/_probe_clerk_size.gd
##
## 输出：每个角色**模型根的缩放**、每块网格的**世界高度**与顶/底面 y。
## 只认名字里带 Body 的身体网格来判断身高（枪、光环、嘴巴不算）。

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 40:
		await process_frame

	_report(game, "芹香", "Shop/ClerkSerika")
	_report(game, "玩家", "Player")
	for want in ["CompanionKoyuki", "CompanionYuuka", "CompanionMomoi"]:
		if game.get_node_or_null(want) != null:
			_report(game, want, want)
	quit(0)


func _report(root_node: Node, label: String, path: String) -> void:
	var n := root_node.get_node_or_null(path) as Node3D
	print("\n===== %s（%s）=====" % [label, path])
	if n == null:
		print("  [缺失]")
		return
	print("  自身 scale = %s；世界位置 %s" % [str(n.scale), str(n.global_position.snappedf(0.01))])
	var meshes := n.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		print("  （没找到网格）")
		return
	var names := PackedStringArray()
	for c in meshes:
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var aabb := mi.get_aabb()
		var w := mi.global_transform * aabb
		print("    %-32s 高 %.3f  顶 %.3f  底 %.3f" % [mi.name, w.size.y,
			w.position.y + w.size.y, w.position.y])
		if String(mi.name).to_lower().contains("body"):
			names.append(mi.name)
	print("  → 身体网格：%s" % (", ".join(names) if names.size() > 0 else "（没认出来）"))

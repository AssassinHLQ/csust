extends SceneTree
## 探针：十个嘴型网格各自的世界 AABB（看它们是不是都在同一个位置、有没有退化）
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 40:
		await process_frame
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	for mi in clerk.find_children("Mouth*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var a: AABB = m.mesh.get_aabb()
		var wa: AABB = m.global_transform * a
		print("  %-10s vis=%s  局部 %s  世界中心 %s  世界尺寸 %s" % [
			m.name, str(m.visible), str(a.size.snappedf(0.0001)),
			str(wa.get_center().snappedf(0.0001)), str(wa.size.snappedf(0.0001))])
	quit(0)

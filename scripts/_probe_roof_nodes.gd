extends SceneTree
## 探针：屋顶那几件东西现在**摆在场景里**（可以在编辑器里选中 / 拖动），
## 而不是运行时才生成。用法：
##   godot --headless --script res://scripts/_probe_roof_nodes.gd -- --splat=off


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var pk := (load("res://scenes/parkour.tscn") as PackedScene).instantiate()
	root.add_child(pk)
	for _i in 10:
		await process_frame
	var shed := pk.get_node_or_null("Island/Props/Shed") as Node3D
	for nm in ["RoofSolid", "RoofSteps", "RTX5090", "BankSign", "Settlement"]:
		var n := shed.get_node_or_null(nm)
		print("[nodes] %-10s %s  global %s" % [nm,
			"有" if n != null else "**没有**",
			str((n as Node3D).global_position.snappedf(0.01)) if n is Node3D else "-"])
	var steps := shed.get_node_or_null("RoofSteps")
	if steps != null:
		print("[nodes] RoofSteps 子节点 %d 个" % steps.get_child_count())
	var gpu := shed.get_node_or_null("RTX5090") as Rtx5090
	if gpu != null:
		print("[nodes] 5090 三角面 %d，子节点 %d" % [gpu.triangle_count(), gpu.get_child_count()])
	var sign_node := shed.get_node_or_null("BankSign") as BankSign
	if sign_node != null:
		print("[nodes] BANK %.2f × %.2f m，%d 面，yaw %.1f°，子节点 %d" % [
			sign_node.width, sign_node.height, sign_node.sign_tris,
			rad_to_deg(sign_node.rotation.y), sign_node.get_child_count()])
	var solid := shed.get_node_or_null("RoofSolid")
	print("[nodes] 屋顶碰撞 %s" % ("有" if solid != null else "**没有**"))
	quit(0)

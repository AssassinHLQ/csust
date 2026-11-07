extends SceneTree
## headless：只验证壁挂机箱场景能加载、8 张 5090 / 显示器 / 碰撞都在位。
##   _tools/run_probe.sh res://scripts/_verify_pc_wall_case_load.gd

func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	ShopClerk._bought = true
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(70)
	var rig := game.get_node_or_null("GameDevRoom/PC5090Rig") as Node3D
	if rig == null:
		print("[wallload] 没找到 PC5090Rig")
		quit(1)
		return
	print("[wallload] rig visible=", rig.visible, " pos=", rig.global_position.snappedf(0.01))
	var gpus := rig.find_children("GPU*", "Node3D", false, false)
	print("[wallload] GPU 节点数=", gpus.size())
	for i in gpus.size():
		var card := gpus[i] as Node3D
		var box := AABB()
		var first := true
		for mi in card.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D)
			if m.mesh == null:
				continue
			var b: AABB = m.global_transform * m.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		print("  %s pos=%s size=%s" % [card.name, str(card.global_position.snappedf(0.01)),
			str(box.size.snappedf(0.001))])
	for i in 2:
		var nm := "Monitor%d" % i
		var mon := rig.get_node_or_null(nm) as Node3D
		if mon == null:
			print("[wallload] 没找到 ", nm)
			continue
		var mb := AABB()
		var mfirst := true
		for mi in mon.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D)
			if m.mesh == null:
				continue
			var b: AABB = m.global_transform * m.mesh.get_aabb()
			mb = b if mfirst else mb.merge(b)
			mfirst = false
		print("[wallload] ", nm, " pos=", mon.global_position.snappedf(0.01),
			" AABB=", str(mb.position.snappedf(0.01)), " size=", str(mb.size.snappedf(0.01)))
	var body := rig.get_node("Body")
	var shapes := 0
	for c in body.get_children():
		if c is CollisionShape3D:
			shapes += 1
	print("[wallload] 碰撞形状=", shapes)
	quit(0)

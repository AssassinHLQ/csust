extends SceneTree
## 探针 A：**岛上的掩体（Shed）下面挂了什么** —— 用户 2026-10-21 截图里那
## 「五个白方块」到底是哪几个节点（`RoofSteps/Step0..2` 只有 3 个，多出来的要查清）。
## 探针 B：609 代理门**斜着仰视**（复现用户第三张截图），看门楣那道竖缝还在不在。
##
## 用法：godot --path <工程> --script res://scripts/_probe_shed_door.gd [-- --splat=off]
## 出图：…/_arisu_captures/_shed/*.png

const OUT_SUB := "_shed"

var _cam: Camera3D
var _out: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 60:
		await process_frame
	var player := game.get_node_or_null("Player") as Player
	if player != null:
		player.set_process_input(false)
	for n in ["HUD", "SettingsMenu", "DialogueBox", "Parkour/ParkourHUD",
			"Parkour/Futures/FuturesHUD"]:
		var c := game.get_node_or_null(n)
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false

	var shed := game.get_node_or_null("Parkour/Island/Props/Shed") as Node3D
	if shed == null:
		print("[shed] 找不到 Shed")
		quit(1)
		return
	print("[shed] 掩体世界坐标 %s，局部 → 世界矩阵 %s" % [
		str(shed.global_position.snappedf(0.01)), str(shed.global_transform.basis)])
	_dump(shed)

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.03
	_cam.far = 500.0
	_cam.current = true
	root.add_child(_cam)

	# 掩体位置 + 台阶那一带（西侧）
	var s := shed.global_position
	await _shot("1_shed_wide", s + Vector3(-9.0, 7.0, 7.0), s + Vector3(0.0, 1.2, 0.0))
	await _shot("2_steps_top", s + Vector3(-6.5, 6.0, 1.0), s + Vector3(-2.6, 0.4, 0.6))
	await _shot("3_steps_low", s + Vector3(-7.5, 1.8, 3.5), s + Vector3(-2.4, 0.8, 0.6))

	# 609 代理门：斜仰视（用户第三张的机位）
	await _shot("4_door_grazing", Vector3(7.4, 1.05, -2.75), Vector3(4.86, 5.00, -2.75))
	await _shot("5_door_grazing_r", Vector3(6.9, 1.05, -1.60), Vector3(4.86, 4.60, -3.20))
	print("\n出图目录：%s" % _out)
	quit(0)


## 把 Shed 底下每个 Node3D 的世界/局部位置、网格尺寸都打出来
func _dump(shed: Node3D) -> void:
	print("[shed] ── 子节点清单 ──")
	for c in shed.get_children():
		var line := "  %-14s %-20s 局部 %s" % [
			String(c.name), c.get_class(), str((c as Node3D).position.snappedf(0.01))]
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh is BoxMesh:
				line += "  Box %s" % str((mi.mesh as BoxMesh).size.snappedf(0.01))
			elif mi.mesh != null:
				line += "  Mesh aabb %s" % str(mi.mesh.get_aabb().size.snappedf(0.01))
			line += "  世界 %s" % str(mi.global_position.snappedf(0.01))
		print(line)
		if c.get_child_count() > 0:
			for g in c.get_children():
				var extra := ""
				if g is MeshInstance3D and (g as MeshInstance3D).mesh is BoxMesh:
					extra = "  Box %s" % str(((g as MeshInstance3D).mesh as BoxMesh).size.snappedf(0.01))
				if g is CollisionShape3D and (g as CollisionShape3D).shape is BoxShape3D:
					extra = "  Col %s" % str(((g as CollisionShape3D).shape as BoxShape3D).size.snappedf(0.01))
				print("      %-12s %-18s 局部 %s%s" % [
					String(g.name), g.get_class(),
					str((g as Node3D).position.snappedf(0.01)), extra])


func _shot(name: String, pos: Vector3, look: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	if Engine.get_frames_drawn() == before:
		print("  [img] 跳过 %s（3 s 内没有新帧）" % name)
		return
	for _i in 8:
		await process_frame
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("[shed] %s ← 相机 %s" % [name, str(pos.snappedf(0.1))])

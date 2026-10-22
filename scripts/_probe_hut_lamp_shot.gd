extends SceneTree
## 验图 + 验数：小屋吊灯是不是真的挂到屋顶上了；同伴站上召唤台后脚在哪儿。
##   godot --path . --script res://scripts/_probe_hut_lamp_shot.gd -- --splat=off
## 输出：_arisu_captures/_lamp/{lamp,lamp_up,companions}.png
func _initialize() -> void:
	_run.call_deferred()


func _shoot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])


## 一个节点下所有 MeshInstance3D 的世界包围盒（含自身）
func _world_aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	var list: Array = []
	if node is MeshInstance3D:
		list.append(node)
	list.append_array(node.find_children("*", "MeshInstance3D", true, false))
	for mi in list:
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_lamp")
	DirAccess.make_dir_recursive_absolute(out)
	var hud := game.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	var hut := game.get_node_or_null("MeshHut") as Node3D
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.05
	cam.far = 400.0
	root.add_child(cam)

	# ── 数：吊灯链条 ──
	var roof_under := 5.70
	for n in ["HutLamp", "LampCord"]:
		var mi := hut.get_node_or_null(n) as MeshInstance3D
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		print("%-9s 世界 y %.3f ~ %.3f（小屋局部 %.3f ~ %.3f）  到屋顶底面 %+.3f m" % [
			n, a.position.y, a.end.y,
			a.position.y - hut.global_position.y, a.end.y - hut.global_position.y,
			hut.global_position.y + roof_under - a.end.y])
	var plate := hut.get_node_or_null("FloorPlate") as MeshInstance3D
	var pa: AABB = plate.global_transform * plate.mesh.get_aabb()
	print("地板顶面 y = %.3f" % pa.end.y)

	# ── 图 ① 站在屋里平视吊灯 ──
	cam.global_position = hut.to_global(Vector3(2.5, 1.55, 2.2))
	cam.look_at(hut.to_global(Vector3(0.0, 4.4, 0.0)), Vector3.UP)
	await _shoot(cam, out, "lamp")

	# ── 图 ② 抬头看灯和屋顶（证明是连着屋顶的）──
	cam.global_position = hut.to_global(Vector3(0.4, 1.2, 2.35))
	cam.look_at(hut.to_global(Vector3(0.0, 5.4, 0.0)), Vector3.UP)
	await _shoot(cam, out, "lamp_up")

	# ── 召唤同伴，量她们的脚 ──
	game.call("_on_summon")
	for _i in 20:
		await process_frame
	var comps: Array = game.get("_companions")
	var floor_y := pa.end.y
	var total := comps.size()
	for i in total:
		var comp := comps[i] as Node3D
		if not is_instance_valid(comp):
			continue
		var cbox := _world_aabb(comp)
		var origin := comp.global_position
		print("同伴 %d/%d  %-14s 原点 y %.3f  模型底 y %.3f（离地板 %+.3f m）" % [
			i + 1, total, comp.name, origin.y, cbox.position.y, cbox.position.y - floor_y])
	if total > 0:
		cam.global_position = hut.to_global(Vector3(-2.6, 1.3, -0.2))
		cam.look_at(hut.to_global(Vector3(1.2, 0.55, 1.2)), Vector3.UP)
		await _shoot(cam, out, "companions")
	print("[截图] %s" % out)
	quit(0)

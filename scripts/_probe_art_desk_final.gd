extends SceneTree
## 出图：画室家具碰撞的**最终贴合**（盒子从 `game.tscn` 读，不是写死的常量）。
##   godot --path . --script res://scripts/_probe_art_desk_final.gd
## 出图：_arisu_captures/_fix1026/{f_desk, f_desk_side, f_desk_walk}.png

const OUT := "_arisu_captures/_fix1026"
var _out_abs := ""


func _initialize() -> void:
	_run.call_deferred()


func _shot(cam: Camera3D, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out_abs, nm])


func _seg(game: Node3D, a: Vector3, b: Vector3, t: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var d := b - a
	bm.size = Vector3(maxf(absf(d.x), t), maxf(absf(d.y), t), maxf(absf(d.z), t))
	mi.mesh = bm
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	game.add_child(mi)


func _wire(game: Node3D, box: AABB, col: Color, t := 0.014) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	var lo := box.position
	var hi := box.position + box.size
	for y in [lo.y, hi.y]:
		for pair in [[Vector3(lo.x, y, lo.z), Vector3(hi.x, y, lo.z)],
				[Vector3(hi.x, y, lo.z), Vector3(hi.x, y, hi.z)],
				[Vector3(hi.x, y, hi.z), Vector3(lo.x, y, hi.z)],
				[Vector3(lo.x, y, hi.z), Vector3(lo.x, y, lo.z)]]:
			_seg(game, pair[0], pair[1], t, m)
	for cx in [lo.x, hi.x]:
		for cz in [lo.z, hi.z]:
			_seg(game, Vector3(cx, lo.y, cz), Vector3(cx, hi.y, cz), t, m)


func _run() -> void:
	root.size = Vector2i(1600, 1000)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 150:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out)
	_out_abs = out
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false

	# 从场景里读盒子（和运行时真正用的那一份完全一致）
	var body := game.get_node_or_null("Room609/RoomCollision") as Node3D
	var cols := [Color(1, 0.1, 0.9), Color(0.2, 1.0, 0.3), Color(0.2, 0.8, 1.0)]
	var i := 0
	var desk_c := Vector3.ZERO
	for nm in ["ArtDesk", "ArtChairA", "ArtChairB"]:
		var cs := body.get_node_or_null(nm) as CollisionShape3D
		if cs == null:
			continue
		var b := cs.shape as BoxShape3D
		var world := AABB(cs.global_position - b.size * 0.5, b.size)
		_wire(game, world, cols[i % cols.size()])
		print("%-11s x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f"
			% [nm, world.position.x, world.end.x, world.position.y, world.end.y,
				world.position.z, world.end.z])
		if i == 0:
			desk_c = cs.global_position
		i += 1

	var sensei := game.get_node_or_null("Sensei") as Node3D
	var sp := sensei.global_position
	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 400.0
	root.add_child(cam)
	cam.fov = 40.0
	cam.global_position = Vector3(sp.x - 1.60, 2.30, sp.z + 3.20)
	cam.look_at(Vector3(sp.x - 1.00, 0.65, sp.z - 0.20), Vector3.UP)
	await _shot(cam, "f_desk")

	cam.fov = 55.0
	cam.global_position = Vector3(desk_c.x + 0.2, 1.30, desk_c.z + 3.20)
	cam.look_at(Vector3(desk_c.x, 0.45, desk_c.z), Vector3.UP)
	await _shot(cam, "f_desk_side")

	# 玩家真的顶在桌前那一刻（撞停以后再拍）
	var player := game.get_node_or_null("Player") as CharacterBody3D
	if player != null:
		player.global_position = Vector3(desk_c.x, 0.10, desk_c.z + 2.6)
		player.velocity = Vector3.ZERO
		for _f in 25:
			await process_frame
		Input.action_press("move_forward")
		for _f in 120:
			await process_frame
		Input.action_release("move_forward")
		for _f in 20:
			await process_frame
		print("玩家停在 z = %.3f（桌前 %.3f）" % [
			player.global_position.z, desk_c.z + 0.53 + 0.30])
		cam.fov = 50.0
		cam.global_position = desk_c + Vector3(1.30, 1.50, 2.20)
		cam.look_at(desk_c + Vector3(0.0, 0.40, 0.30), Vector3.UP)
		await _shot(cam, "f_desk_walk")

	print("\n[截图] %s" % out)
	quit(0)

extends SceneTree
## 探针：小空的**待机动画**到底导进来没有、手臂有没有真的放下来。
##
## 判据不看 AABB（蒙皮网格的 `get_aabb()` 是绑定姿态），看 `hand.l` 骨的世界 y：
##   A-pose 时是 0.89 m；手臂放下后应该掉到 0.6 上下，而且随时间轻微起伏（呼吸）。
## 同时拍两张不同时刻的图，肉眼确认姿势。
##
## 用法：godot --path <工程> --script res://scripts/_probe_sora_idle.gd -- --no-capture
## 输出：`_arisu_captures/_sora/idle_t0.png` / idle_t1.png

const MODEL := "res://models/npc/sora/sora.glb"
const OUT := "_sora"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(900, 1100)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.15, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.3
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(20, 1, 20)
	ground.mesh = bm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.32, 0.36)
	gm.roughness = 0.95
	ground.material_override = gm
	ground.position = Vector3(0, -0.5, 0)
	root.add_child(ground)

	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	for _i in 20:
		await process_frame

	var skel := _best(model)
	var hand := _find(skel, "hand.l")
	var aps := _all(model, "AnimationPlayer")
	print("── 小空 GLB ──")
	print("  骨架 %d 骨，hand.l=%d，AnimationPlayer %d 个"
		% [skel.get_bone_count() if skel else 0, hand, aps.size()])
	for a in aps:
		var ap := a as AnimationPlayer
		print("  动画：%s" % str(ap.get_animation_list()))
		if ap.get_animation_list().has("Idle"):
			ap.play("Idle")
			ap.seek(0.05, true)
			print("  播放「Idle」（长度 %.2f s）" % ap.get_animation("Idle").length)

	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.02
	cam.far = 200.0
	root.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(0.6, 1.05, 3.2)
	cam.look_at(Vector3(0, 0.85, 0), Vector3.UP)

	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out_dir)

	for i in 3:
		var t := 0.05 + float(i) * 0.9
		for a in aps:
			var ap := a as AnimationPlayer
			if ap.get_animation_list().has("Idle"):
				ap.seek(t, true)
		await _frames(4)
		var y := _bone_y(skel, hand)
		print("  t=%.2fs  hand.l 世界 y = %.3f m" % [t, y])
		await _shot(out_dir.path_join("idle_t%d.png" % i))
	print("\n出图：%s" % out_dir)
	quit(0)


func _bone_y(skel: Skeleton3D, idx: int) -> float:
	if skel == null or idx < 0:
		return -999.0
	return (skel.global_transform * skel.get_bone_global_pose(idx).origin).y


func _find(skel: Skeleton3D, want: String) -> int:
	if skel == null:
		return -1
	for i in skel.get_bone_count():
		if skel.get_bone_name(i) == want:
			return i
	return -1


func _best(node: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	for n in _all(node, "Skeleton3D"):
		var s := n as Skeleton3D
		if best == null or s.get_bone_count() > best.get_bone_count():
			best = s
	return best


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	for _i in 5:
		await process_frame
	root.get_texture().get_image().save_png(path)
	print("[shot] %s" % path.get_file())


func _all(node: Node, cls: String) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		out.append_array(_all(c, cls))
	return out

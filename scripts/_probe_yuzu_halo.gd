extends SceneTree
## 探针：柚子光环的渲染 + 柚子/小桃/小绿的跑步姿势（用户报「头右倾」）。
##
## 一次看三件事：
##   ① 七只真人排开，柚子特写（光环材质：透明度 / 自发光 / 双面 / 混合模式）
##   ② 三只一起播 `Move_Ing`，正面 + 侧面各一张，看头是不是歪的
##   ③ 把「头骨相对胯骨」的偏航角量出来（数值判定，不靠眼睛）
##
## 用法：godot --path <工程> --script res://scripts/_probe_yuzu_halo.gd -- --no-capture
## 输出：`_arisu_captures/_companion/98_yuzu_halo.png` / 99_run_front.png / 99b_run_side.png

const CompanionScene := preload("res://scenes/companion.tscn")
const OUT := "_companion"
const TARGETS := [
	["柚子", "res://models/companions/Yuzu.glb"],
	["小桃", "res://models/companions/Momoi.glb"],
	["小绿", "res://models/companions/Midori.glb"],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1400, 900)
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
	sun.rotation_degrees = Vector3(-50, 25, 0)
	sun.light_energy = 1.3
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(30, 1, 30)
	ground.mesh = bm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.32, 0.36)
	gm.roughness = 0.95
	ground.material_override = gm
	ground.position = Vector3(0, -0.5, 0)
	root.add_child(ground)

	var placed: Array = []
	for i in TARGETS.size():
		var c := CompanionScene.instantiate() as Node3D
		c.set("display_name", TARGETS[i][0])
		c.set("model_path", TARGETS[i][1])
		c.set("model_y_offset", -0.035)
		root.add_child(c)
		c.global_position = Vector3((float(i) - 1.0) * 1.6, 0.05, 0.0)
		c.rotation.y = 0.0
		placed.append(c)
	for _i in 30:
		await process_frame

	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.02
	cam.far = 200.0
	root.add_child(cam)
	cam.make_current()

	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out_dir)

	# ── ① 柚子光环材质 ──
	var yuzu: Node3D = null
	for c in placed:
		if String(c.get("display_name")) == "柚子":
			yuzu = c
	if yuzu != null:
		print("\n── 柚子材质 ──")
		for mi in _all(yuzu, "MeshInstance3D"):
			var g := mi as MeshInstance3D
			var am := g.mesh as ArrayMesh
			if am == null:
				continue
			for s in am.get_surface_count():
				var mat := am.surface_get_material(s)
				if mat is StandardMaterial3D:
					var sm := mat as StandardMaterial3D
					print("  %-22s %-18s transp=%d cull=%d unshaded=%s emis=%s alpha=%.2f"
						% [g.name, sm.resource_name, sm.transparency, sm.cull_mode,
							str(sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED),
							str(sm.emission_enabled), sm.albedo_color.a])
		var p := yuzu.global_position
		cam.global_position = p + Vector3(0.0, 1.35, 1.15)
		cam.look_at(p + Vector3(0.0, 1.30, 0.0), Vector3.UP)
		await _shot(out_dir.path_join("98_yuzu_halo.png"))

	# ── ② 三只跑步：正面 + 侧面 ──
	for c in placed:
		var anim: Node = c.get("anim")
		if anim != null:
			anim.call("set_locomotion", 2.4, true, 0.0)
			if anim.get("player") is AnimationPlayer:
				(anim.get("player") as AnimationPlayer).play("Move_Ing", -1.0, 1.0)
	for _i in 20:
		await process_frame
	cam.global_position = Vector3(0.0, 1.15, 4.6)
	cam.look_at(Vector3(0.0, 0.85, 0.0), Vector3.UP)
	await _shot(out_dir.path_join("99_run_front.png"))
	cam.global_position = Vector3(4.6, 1.15, 0.0)
	cam.look_at(Vector3(0.0, 0.85, 0.0), Vector3.UP)
	await _shot(out_dir.path_join("99b_run_side.png"))

	# ── ③ 头相对胯的偏航角 ──
	print("\n── 头骨朝向（世界坐标，看有没有歪）──")
	for c in placed:
		var skel := _best(c)
		if skel == null:
			continue
		var head := _bone_pos(skel, "head.x", "Head", "head")
		var hips := _bone_pos(skel, "hips.x", "Hips", "pelvis")
		var eyes := _eye_dir(skel)
		print("  %-4s 头骨 %s  眼方向 %s  头-胯水平偏移 %.3f m"
			% [c.get("display_name"), str(head.snappedf(0.01)),
				str(eyes.snappedf(0.01)), Vector2(head.x - hips.x, head.z - hips.z).length()])

	print("\n出图：%s" % out_dir)
	quit(0)


func _bone_pos(skel: Skeleton3D, a: String, b: String, c: String) -> Vector3:
	for want in [a, b, c]:
		for i in skel.get_bone_count():
			if skel.get_bone_name(i).to_lower() == want.to_lower():
				return skel.global_transform * skel.get_bone_global_pose(i).origin
	return Vector3.ZERO


func _eye_dir(skel: Skeleton3D) -> Vector3:
	var l := Vector3.ZERO
	var r := Vector3.ZERO
	var found_l := false
	var found_r := false
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i).to_lower()
		if n.begins_with("eye") and n.ends_with(".l"):
			l = skel.global_transform * skel.get_bone_global_pose(i).origin
			found_l = true
		elif n.begins_with("eye") and n.ends_with(".r"):
			r = skel.global_transform * skel.get_bone_global_pose(i).origin
			found_r = true
	if not (found_l and found_r):
		return Vector3.ZERO
	return (r - l).normalized()


func _best(node: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	for n in _all(node, "Skeleton3D"):
		var s := n as Skeleton3D
		if best == null or s.get_bone_count() > best.get_bone_count():
			best = s
	return best


func _all(node: Node, cls: String) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		out.append_array(_all(c, cls))
	return out


func _shot(path: String) -> void:
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	for _i in 6:
		await process_frame
	root.get_texture().get_image().save_png(path)
	print("[shot] %s" % path.get_file())

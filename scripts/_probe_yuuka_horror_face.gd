extends SceneTree
## 出图：恐怖优香的脸部近景（看新眼贴图在 horror_skin 着色器下的样子）。
##
##   bash _tools/run_shot.sh res://scripts/_probe_yuuka_horror_face.gd
##
## 输出：_arisu_captures/_yuuka_eye/horror_face.png

const OffWin := preload("res://scripts/offscreen_window.gd")
const BOSS_SCRIPT := "res://scripts/yuuka_horror_boss.gd"
const ORIG_TEX := "res://models/companions/Yuuka_Yuuka_Original_EyeMouth.png"
const SHOTS_REL := "_arisu_captures/_yuuka_eye"


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(900, 900))
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	var wd := create_timer(240.0, true)
	wd.timeout.connect(func() -> void:
		print("[face] !! 看门狗超时")
		quit(2))
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(900, 900))

	var world := Node3D.new()
	root.add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.10, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	sun.light_energy = 1.2
	world.add_child(sun)

	var boss := (load(BOSS_SCRIPT) as GDScript).new() as Node3D
	world.add_child(boss)
	for _i in 20:
		await process_frame

	var model := boss.get("model") as Node3D
	if model == null:
		print("[face] ✗ 没有 model")
		quit(1)
		return

	var box := _world_aabb(model)
	var eye := _eye_center(model)
	if eye == Vector3.ZERO:
		eye = Vector3(box.get_center().x, box.position.y + box.size.y * 0.76, box.get_center().z)
	print("[face] 模型包围盒 %s\n[face] 眼嘴面中心 %s" % [str(box), str(eye)])

	var cam := Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.05
	cam.far = 500.0
	world.add_child(cam)
	cam.current = true

	var dir := ProjectSettings.globalize_path("res://").path_join(SHOTS_REL)
	DirAccess.make_dir_recursive_absolute(dir)
	var dist := box.size.y * 1.15
	var aim := Vector3(box.get_center().x, box.position.y + box.size.y * 0.62, box.get_center().z)
	cam.global_position = aim + Vector3(0.0, box.size.y * 0.10, dist)
	cam.look_at(aim, Vector3.UP)
	for _i in 10:
		await process_frame

	# ① 眼睛自发光（脚本设的值）
	await RenderingServer.frame_post_draw
	var p1 := dir.path_join("horror_face_emit_on.png")
	print("[face] err=%d → %s（eye_emit=%.2f）"
		% [root.get_texture().get_image().save_png(p1), p1.get_file(), _eye_emit_of(model)])

	# ② 关掉自发光做 A/B
	_override_eye_tex(model, null, 0.0)
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var p2 := dir.path_join("horror_face_emit_off.png")
	print("[face] err=%d → %s" % [root.get_texture().get_image().save_png(p2), p2.get_file()])

	# ③ 换回原图（只对照）
	_override_eye_tex(model, load(ORIG_TEX) as Texture2D, -1.0)
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var p3 := dir.path_join("horror_face_orig.png")
	print("[face] err=%d → %s" % [root.get_texture().get_image().save_png(p3), p3.get_file()])
	quit(0)


func _eye_emit_of(n: Node3D) -> float:
	var om := _eye_override(n)
	if om == null:
		return -1.0
	var raw = om.get_shader_parameter("eye_emit")
	return -1.0 if raw == null else float(raw)


## tex 传 null = 不改；emit < 0 = 不改。
func _override_eye_tex(n: Node3D, tex: Texture2D, emit: float) -> void:
	var om := _eye_override(n)
	if om == null:
		return
	if tex != null:
		om.set_shader_parameter("albedo_tex", tex)
	if emit >= 0.0:
		om.set_shader_parameter("eye_emit", emit)


func _eye_override(n: Node3D) -> ShaderMaterial:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			if not mat.albedo_texture.resource_path.contains("EyeMouth"):
				continue
			return m.get_surface_override_material(s) as ShaderMaterial
	return null


## 眼嘴那一面的顶点包围盒中心（世界坐标）——比整模型包围盒准，不会被光环带偏。
func _eye_center(n: Node3D) -> Vector3:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			var p := mat.albedo_texture.resource_path
			if not p.contains("EyeMouth") or p.contains("Character_Mouth"):
				continue
			var arr := m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var xf := m.global_transform
			var lo := xf * verts[0]
			var hi := lo
			for v in verts:
				var w := xf * v
				lo = lo.min(w)
				hi = hi.max(w)
			return (lo + hi) * 0.5
	return Vector3.ZERO


func _world_aabb(n: Node3D) -> AABB:
	var first := true
	var out := AABB()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b := m.global_transform * m.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
